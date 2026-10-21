/* =========================================================
   Le solde de la boutique, et ses reversements, à l'écran (3.59.0)
   =========================================================
   La base calcule et décide (supabase/tests/99zzzzzzzzzzzzzzzzzzzzz-
   solde-boutique.sql). Ce banc regarde l'application admin :

     1. l'administrateur de la boutique voit son solde : disponible, d'où
        il vient, ce qui est à venir ; son accueil y mène ;
     2. il règle le numéro de réception (réseau, numéro, titulaire) ;
     3. il demande un reversement : le montant part vers la base ;
     4. un modérateur n'y entre pas ;
     5. le superadministrateur voit les demandes, valide avec la
        référence, ou refuse avec un motif.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-solde-boutique.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const plat = (s) => s.replace(/[  ]/g, " ").replace(/\s+/g, " ");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const jeton = (sub) => {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return b64({ alg: "HS256" }) + "." + b64({ sub }) + ".s";
};
const CHEF = "c1c10000-0000-0000-0000-000000000001";
const MODO = "c1c10000-0000-0000-0000-000000000002";
const SUP = "11111111-1111-1111-1111-111111111111";
const PROFILS = {
  [CHEF]: { id: CHEF, email: "chef@alpha.bj", nom: "Chef", role: "administrateur", actif: true, boutique_id: "bou_a", peut_modifier_produits: true },
  [MODO]: { id: MODO, email: "modo@alpha.bj", nom: "Modo", role: "moderateur", actif: true, boutique_id: "bou_a", peut_modifier_produits: true },
  [SUP]: { id: SUP, email: "sup@bizzoo.bj", nom: "Sup", role: "superadministrateur", actif: true, boutique_id: null, peut_modifier_produits: true },
};
const BOU = [{ id: "bou_a", nom: "Alpha", categorie_id: null, icone: "magasin", couleur: "#0047D9",
  devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }];
const DEMANDE = { id: 7, boutique_id: "bou_a", nom_boutique: "Alpha", montant: 10000, tel: "0196123456", reseau: "MTN",
  titulaire: "Chef", etat: "en_attente", demande_par: "Chef", demande_le: "2026-10-20T10:00:00Z", decide_par: "",
  decide_le: null, reference: "", motif: "", devise: "FCFA" };

async function ouvrir(moi, hash, { reception = null } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2000 } });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
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
    if (c.startsWith("rpc/")) rpc.push({ nom: c.slice(4), corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })() });
    if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    if (c === "rpc/solde_boutique") return d({ gagne: 16000, a_venir: 4000, deja_encaisse: 0, reverse: 0, en_attente: 0,
      disponible: 16000, devise: "FCFA", reception });
    if (c === "rpc/reversements_liste") return d(moi === SUP ? [DEMANDE] : []);
    if (c === "rpc/regler_reception") return d({ tel: "0196123456", reseau: "MTN" });
    if (c === "rpc/demander_reversement") return d(8);
    if (c === "rpc/decider_reversement") return d("valide");
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
const vue = (page) => page.evaluate(() => document.getElementById("vue").innerText).then(plat);

titre("1-3. L'administrateur de la boutique");
{
  const o = await ouvrir(CHEF, "");
  ok(!!(await o.page.$('#ac-solde[href="#/solde"]')), "son accueil mène au solde");
  await o.page.evaluate(() => { location.hash = "#/solde"; });
  await pause(1500);
  const t = await vue(o.page);
  ok(/Disponible/i.test(t) && /16 000 FCFA/.test(t) && /À venir/.test(t) && /4 000 FCFA/.test(t),
    "le solde : 16 000 disponibles, 4 000 à venir");
  ok(await o.page.evaluate(() => document.querySelector("#sd-demander").disabled) && /Réglez d'abord le numéro/.test(t),
    "sans numéro : « Demander un reversement » est grisé, et on dit pourquoi");
  await o.page.click("#sd-regler");
  await pause(400);
  await o.page.click('[data-reseau="MTN"]');
  await o.page.fill("#sd-tel", "01 96 12 34 56");
  await o.page.fill("#sd-titulaire", "Chef Alpha");
  await o.page.click("#sd-enregistrer");
  await pause(1200);
  const r = o.rpc.find((x) => x.nom === "regler_reception");
  ok(r && r.corps.cible === "bou_a" && r.corps.reseau === "MTN" && r.corps.tel === "01 96 12 34 56" && r.corps.titulaire === "Chef Alpha",
    "regler_reception(bou_a, 01 96 12 34 56, MTN, Chef Alpha)");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}
{
  const o = await ouvrir(CHEF, "#/solde", { reception: { tel: "0196123456", reseau: "MTN", titulaire: "Chef", maj_le: "2026-10-20T09:00:00Z", maj_par: "Chef" } });
  ok(/MTN 0196123456/.test(await vue(o.page)), "le numéro réglé s'affiche");
  await o.page.click("#sd-demander");
  await pause(400);
  await o.page.fill("#sd-montant", "10000");
  await o.page.click("#sd-envoyer");
  await pause(1200);
  const r = o.rpc.find((x) => x.nom === "demander_reversement");
  ok(r && r.corps.cible === "bou_a" && r.corps.montant === 10000, "demander_reversement(bou_a, 10 000)");
  await o.ctx.close();
}

titre("4. Un modérateur : non");
{
  const o = await ouvrir(MODO, "#/solde");
  ok(/Réservé à l'administrateur/.test(await vue(o.page)) && !o.rpc.some((x) => x.nom === "solde_boutique"),
    "« Réservé à l'administrateur », rien n'est lu");
  ok(!(await o.page.$("#ac-solde")), "et son accueil n'en parle pas");
  await o.ctx.close();
}

titre("5. Le superadministrateur");
{
  const o = await ouvrir(SUP, "");
  ok(!!(await o.page.$('#ac-reversements[href="#/reversements"]')), "son accueil mène aux reversements");
  await o.page.evaluate(() => { location.hash = "#/reversements"; });
  await pause(1500);
  const t = await vue(o.page);
  ok(/1 demande à traiter/i.test(t) && /Alpha/.test(t) && /10 000 FCFA/.test(t) && /MTN 0196123456/.test(t),
    "la demande d'Alpha : 10 000 vers MTN 0196123456");
  await o.page.click("[data-valider]");
  await pause(400);
  await o.page.fill("#feuille-corps input, #feuille-corps textarea", "MP-998877");
  await o.page.click('#feuille-corps [data-role="ok"]');
  await pause(1200);
  const r = o.rpc.find((x) => x.nom === "decider_reversement");
  ok(r && r.corps.cible === 7 && r.corps.accord === true && r.corps.reference === "MP-998877",
    "« Envoyé » : decider_reversement(7, oui, MP-998877)");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " ÉCHEC(S)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
