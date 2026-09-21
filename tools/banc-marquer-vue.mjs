/* =========================================================
   « Marquer vue » : ce que l'application demande à la base
   =========================================================
   LE DÉFAUT QU'ON DÉFEND ICI. PostgREST ajoute « returning * »
   quand on lui demande la ligne en retour. « commande_lignes »
   a une lecture restreinte par colonne — l'équipe ne voit ni le
   prix BIZZOO ni le taux de marge —, alors la base refusait
   TOUTE la requête. L'écriture était pourtant permise : c'est
   le retour qui la faisait tomber.

   Le constat porte donc sur l'EN-TÊTE, parce que c'est lui qui
   décide. Regarder « l'état a changé à l'écran » n'aurait rien
   prouvé : l'écran se repeint avant la réponse de la base.
   ========================================================= */
/* Playwright n'est pas une dépendance du projet : le chemin se donne
   par PLAYWRIGHT, le navigateur par CHROMIUM, l'adresse par BANC_URL. */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-marquer-vue.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const MOI = "22222222-2222-2222-2222-222222222222";
const BOU = [{ id:"bou_tech", nom:"IMPACT", secteur:"Informatique", categorie_id:"cat_h",
  icone:"portable", couleur:"#0B5CF5", devise:"FCFA", indicatif:"229", actif:true, ordre:1 }];
const LIGNE = { id:"lig_vue", commande_id:"cmd_vue", boutique_id:"bou_tech",
  produit_id:"prod_hp", nom:"M10 BT Wireless V5.3", code:"100052",
  reference:"Écouteurs bt", prix:1650, quantite:1, etat:"nouvelle",
  cree_le:"2026-09-12T09:00:00Z", confirme_le:null };
const CMD = [{ id:"cmd_vue", numero:"BZ-000011", client_nom:"Rohim",
  client_tel:"0197592772", client_indicatif:"229", client_adresse:"Godomey ayimevo",
  note:"", total:1650, devise:"FCFA", etat:"payee", transaction_id:"tx1",
  confirme_par:"", remarque:"", paye_le:"2026-09-12T09:02:00Z",
  cree_le:"2026-09-12T09:00:00Z", commande_lignes:[LIGNE] }];

const ctx = await nav.newContext({ viewport:{ width:390, height:1700 } });
const page = await ctx.newPage();
page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));
const ecritures = [];

await page.addInitScript((moi) => {
  localStorage.setItem("impact-config", JSON.stringify({
    url:"https://base-absente.invalid", cle:"cle-de-banc" }));
  const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
    .replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
  localStorage.setItem("impact-session", JSON.stringify({
    access_token: b64({alg:"HS256"}) + "." + b64({sub:moi}) + ".s",
    refresh_token:"r", expire_a: Date.now()+3600000, email:"chef@impact.bj" }));
}, MOI);

await page.route("**/rest/v1/**", (route) => {
  const req = route.request();
  const u = new URL(req.url());
  const c = u.pathname.replace(/^.*\/rest\/v1\//,"");
  if (req.method() !== "GET") {
    ecritures.push({ methode:req.method(), chemin:c + u.search,
      prefer: req.headers()["prefer"] || "", corps:(() => {
        try { return req.postDataJSON(); } catch (_) { return null; } })() });
  }
  const d = (x) => route.fulfill({status:200,contentType:"application/json",body:JSON.stringify(x)});
  /* La base RÉPOND COMME LA VRAIE : rien du tout quand on lui demande
     « return=minimal ». Une doublure qui renverrait la ligne masquerait
     précisément ce qu'on éprouve. */
  if (req.method() === "PATCH" && /commande_lignes/.test(c)) {
    if (/minimal/.test(req.headers()["prefer"] || "")) {
      return route.fulfill({ status:204, body:"" });
    }
    /* « returning * » sur une table à lecture restreinte : la base
       répond 403, exactement comme chez le gérant. */
    return route.fulfill({ status:403, contentType:"application/json",
      body: JSON.stringify({ message:"permission denied for table commande_lignes" }) });
  }
  if (c.startsWith("profils")) return d([{ id:MOI, email:"chef@impact.bj",
    role:"administrateur", actif:true, peut_modifier_produits:true, boutique_id:"bou_tech" }]);
  if (c.startsWith("commandes")) return d(CMD);
  if (c.startsWith("boutiques")) return d(BOU);
  if (c.startsWith("produits")) return d([]);
  if (c.startsWith("boutique")) return d([{id:1,nom:"BIZZOO",devise:"FCFA",indicatif:"229"}]);
  return d([]);
});

await page.goto(BASE + "/admin/index.html", { waitUntil:"domcontentloaded" });
await page.waitForTimeout(1600);
await page.evaluate(() => { location.hash = "#/commandes"; });
await page.waitForTimeout(1800);

titre("L'écran des commandes s'ouvre sur la ligne à suivre");
{
  const t = await page.evaluate(() => document.body.innerText);
  ok(/BZ-000011/.test(t), "la commande est là");
  ok(/Marquer vue/i.test(t), "et le bouton « Marquer vue » aussi");
}

titre("On appuie : ce qui part vers la base");
{
  await page.evaluate(() => {
    const b = [...document.querySelectorAll("button")]
      .find((x) => /marquer vue/i.test(x.textContent));
    if (b) b.click();
  });
  await page.waitForTimeout(1200);

  const e = ecritures.find((x) => /commande_lignes/.test(x.chemin));
  ok(!!e, "une modification part vers la base");
  ok(e && e.methode === "PATCH", "c'est bien une modification (" +
    (e ? e.methode : "rien") + ")");
  ok(e && e.corps && e.corps.etat === "vue",
    "elle ne change que l'état, et le met à « vue »");
  ok(e && Object.keys(e.corps || {}).length === 1,
    "et rien d'autre ne part (" + (e ? Object.keys(e.corps||{}).join(", ") : "") + ")");
  /* LE CONSTAT QUI DÉFEND LE CORRECTIF. */
  ok(e && /return=minimal/.test(e.prefer),
    "elle ne réclame PAS la ligne en retour (Prefer: " + (e ? e.prefer : "") + ")");
}

titre("Et l'écran ne montre plus de refus");
{
  const t = await page.evaluate(() => document.body.innerText);
  ok(!/n'a pas ce droit/i.test(t),
    "aucun « votre compte n'a pas ce droit »");
  ok(!/refusée par la base/i.test(t), "aucun refus de la base");
}

await ctx.close();
await nav.close();
console.log("\n" + (echecs ? "  " + echecs + " ÉCHEC(S)" : "  Tout passe."));
process.exit(echecs ? 1 : 0);
