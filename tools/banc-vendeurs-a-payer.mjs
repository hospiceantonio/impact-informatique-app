/* =========================================================
   Les vendeurs à payer, en tête et en couleur (4.3.0)
   =========================================================
   Dans l'écran « Vendeurs » du superadministrateur :
   1. d'abord ceux qui ont DEMANDÉ un versement (le plus gros d'abord),
      puis ceux à qui BIZZOO doit de l'argent (le plus gros d'abord),
      puis les autres, par nom ;
   2. ces vendeurs à payer ont leur bandeau de couleur, plus foncé pour une
      demande, et le montant dans une pastille ;
   3. le titre compte ceux qui sont à payer ; la recherche marche toujours.

     PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-vendeurs-a-payer.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-vendeurs-a-payer.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
const SORTIE = process.env.CAPTURES || "";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const SUPER = "11111111-1111-1111-1111-111111111111";
const V = (n, nom, o = {}) => ({ id: "c7c7c7c7-0000-0000-0000-00000000000" + n, nom, tel: "019770000" + n,
  actif: true, produits: 2, ventes: 0, part: 0, commission: 0, a_venir: 0, reverse: 0, en_attente: 0, disponible: 0, ...o });
/* Dans l'ordre des noms, exprès : le tri doit les déplacer. */
const VENTES = [
  V(1, "Akiba cosmétique"),
  V(2, "Artisan bronzier", { disponible: 1080, ventes: 1200, part: 1080, commission: 120 }),
  V(3, "Authentic cosmetique", { en_attente: 2430, ventes: 2700, part: 2430, commission: 270 }),
  V(4, "Azerty"),
  V(5, "Baby style", { disponible: 5000, ventes: 5600, part: 5000, commission: 600 }),
  V(6, "Zénith", { en_attente: 9000, disponible: 400, ventes: 10500, part: 9400, commission: 1100 }),
  V(7, "Bijoux d'Afi", { a_venir: 3000 }),
];

async function ouvrir() {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1800 }, serviceWorkers: "block", locale: "fr-FR" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((m) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: m }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: "x@bizzoo.bj" }));
  }, SUPER);
  await page.route("**/rest/v1/**", (route) => {
    const url = new URL(route.request().url());
    const c = url.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/ventes_vendeurs") return d(VENTES);
    if (c.startsWith("rpc/")) return d([]);
    if (c.startsWith("profils")) {
      const moi = { id: SUPER, email: "x@bizzoo.bj", role: "superadministrateur", actif: true, nom: "Moi",
        peut_modifier_produits: true, boutique_id: null };
      const voulu = (url.searchParams.get("id") || "").replace(/^eq\./, "");
      if (voulu) return d([moi].filter((p) => p.id === voulu));
      return d([moi, ...VENTES.map((v) => ({ id: v.id, email: "", role: "vendeur", actif: true, nom: v.nom,
        tel: v.tel, peut_modifier_produits: true, boutique_id: null }))]);
    }
    if (c.startsWith("boutique") && !c.startsWith("boutiques")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  await page.evaluate(() => { location.hash = "#/vendeurs"; });
  await page.waitForTimeout(1800);
  return { page, ctx, erreurs };
}

titre("1. Les vendeurs à payer en tête de la liste");
{
  const { page, ctx, erreurs } = await ouvrir();
  const l = await page.evaluate(() => [...document.querySelectorAll("#vv-liste .vv-rangee")].map((r) => ({
    nom: (r.querySelector(".sd-ligne-haut strong") || {}).textContent || "",
    aPayer: r.classList.contains("vv-a-payer"), demande: r.classList.contains("vv-demande"),
    mot: ((r.querySelector(".vv-a-payer-mot") || {}).textContent || "").replace(/\s+/g, " ").trim(),
    fond: getComputedStyle(r).backgroundColor,
  })));
  const noms = l.map((x) => x.nom);
  ok(noms.join(" | ") === "Zénith | Authentic cosmetique | Baby style | Artisan bronzier | Akiba cosmétique | Azerty | Bijoux d'Afi",
    "les demandes de versement d'abord (9 000, 2 430), puis ce qu'on doit (5 000, 1 080), puis les autres par nom");
  ok(l.slice(0, 4).every((x) => x.aPayer) && l.slice(4).every((x) => !x.aPayer), "les quatre à payer ont leur bandeau, pas les autres");
  ok(l[0].demande && l[1].demande && !l[2].demande, "une demande de versement a le bandeau le plus foncé");
  ok(l[0].fond !== l[2].fond && l[2].fond !== l[5].fond, "trois teintes : demande, à verser, rien à payer (" +
    [l[0].fond, l[2].fond, l[5].fond].join(" / ") + ")");
  ok(/Demande de versement : 9\s000 FCFA/.test(l[0].mot), "la demande, avec son montant (" + l[0].mot + ")");
  ok(/À verser : 5\s000 FCFA/.test(l[2].mot), "ce qu'on doit, avec son montant (" + l[2].mot + ")");
  ok(l[6].mot === "", "un vendeur dont l'argent est « à venir » (pas encore livré) n'est pas à payer");
  const titreListe = await page.evaluate(() => (document.querySelector("#vv-liste") || {}).previousElementSibling
    ? [...document.querySelectorAll(".titre-section")].map((x) => x.textContent).join(" | ") : "");
  ok(/7 vendeurs · 4 à payer/.test(titreListe.replace(/\s+/g, " ")), "le titre les compte (" + titreListe.replace(/\s+/g, " ") + ")");
  /* La recherche marche toujours sur la liste triée. */
  await page.fill("#vv-chercher", "baby");
  await page.waitForTimeout(200);
  const vus = await page.evaluate(() => [...document.querySelectorAll("#vv-liste .vv-rangee")]
    .filter((r) => !r.hidden).map((r) => r.querySelector("strong").textContent));
  ok(vus.length === 1 && vus[0] === "Baby style", "la recherche trouve toujours un vendeur (" + vus.join(", ") + ")");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  if (SORTIE) {
    await page.fill("#vv-chercher", "");
    await page.waitForTimeout(200);
    const liste = await page.$("#vv-liste");
    await liste.screenshot({ path: SORTIE + "/vendeurs-a-payer.png" });
  }
  await ctx.close();
}

await nav.close();
console.log("\n" + (echecs ? "  " + echecs + " ÉCHEC(S)" : "  Tout passe."));
process.exit(echecs ? 1 : 0);
