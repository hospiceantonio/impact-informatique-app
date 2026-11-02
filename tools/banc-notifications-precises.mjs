/* =========================================================
   Banc — chaque notification mène à l'écran exact (3.73.0)

   La base écrit des liens précis (supabase/tests/99…-notifications-
   precises.sql). Ce banc ouvre BIZZOO Admin sur chacun, comme le ferait
   la touche d'une notification sur le téléphone :

     1. « #/livraisons/<commande> » (nouvelle course) : la carte de CETTE
        course, amenée sous les yeux et marquée ; l'adresse redevient la
        liste ; une course déjà prise : on le dit ;
     2. « #/reversements/livreur-7 » : CETTE demande, marquée ;
     3. « #/comptes/<id> » (compte à valider) : sa fiche s'ouvre ;
     4. « #/commande/<id> » (adresse du reçu client) : la commande ;
     5. « #/stock?filtre=rupture » : le stock, filtré.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-notifications-precises.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const BIZ = "cccccccc-2222-2222-2222-222222222222";
const CHEF = "22222222-2222-2222-2222-222222222222";
const MODO = "33333333-2222-2222-2222-222222222222";
const SUP = "11111111-1111-1111-1111-111111111111";
const PROFILS = {
  [BIZ]: { id: BIZ, email: "biz@bizzoo.bj", nom: "Codjo", role: "livreur", actif: true,
    peut_modifier_produits: false, boutique_id: null, disponible: true },
  [CHEF]: { id: CHEF, email: "chef@alpha.bj", nom: "Chef", role: "administrateur", actif: true,
    peut_modifier_produits: true, boutique_id: "bou_a" },
  [MODO]: { id: MODO, email: "modo.attente@bizzoo.bj", nom: "Modo en attente", role: "moderateur", actif: false,
    a_valider: true, peut_modifier_produits: false, boutique_id: null },
  [SUP]: { id: SUP, email: "sup@bizzoo.bj", nom: "Sup", role: "superadministrateur", actif: true,
    peut_modifier_produits: true, boutique_id: null },
};
const course = (id, numero) => ({ commande_id: id, numero, boutique_id: "bou_a", nom_boutique: "Alpha",
  client_nom: "Afi", client_tel: "97666007", client_indicatif: "229", client_adresse: "Fidjrossè", note: "",
  etat: "preparee", articles: [{ nom: "Casque", quantite: 1 }], paye_le: "2026-10-20T08:00:00Z",
  a_encaisser: 0, recu_le: null,
  fiche: { numero, retrait: { boutique: "Alpha", adresse: "Ganhi", tel: "0197111222", indicatif: "229" },
    livraison: { nom: "Afi", adresse: "Fidjrossè", note: "", tel: "97666007", indicatif: "229" },
    devise: "FCFA", frais: 1000, deja_paye: 4000, a_encaisser: 0, encaisse: null } });
const COURSES = [course("cmd_r", "BZ-000090"), course("cmd_s", "BZ-000091")];
const DEMANDE = (id, o = {}) => ({ id, montant: 1500, tel: "0167332135", reseau: "MTN", titulaire: "",
  etat: "en_attente", demande_le: "2026-10-31T1" + id + ":00:00Z", decide_par: "", decide_le: null, reference: "", motif: "", ...o });

async function ouvrir(moi, adresse) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 900 }, serviceWorkers: "block" });
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
  await page.route("**/rest/v1/**", (route) => {
    const u = new URL(route.request().url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    if (c.startsWith("profils")) {
      const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      return d(id ? [PROFILS[id]].filter(Boolean) : Object.values(PROFILS));
    }
    if (c.startsWith("positions_livreurs")) return d([{ profil_id: BIZ, latitude: 6.37, longitude: 2.42, adresse: "Cotonou" }]);
    if (c === "rpc/mes_livraisons") return d(COURSES);
    if (c === "rpc/courses_proposees") return d([]);
    if (c === "rpc/reversements_liste") return d([DEMANDE(3, { boutique_id: "bou_a", nom_boutique: "Alpha", demande_par: "Chef", devise: "FCFA" })]);
    if (c === "rpc/reversements_livreurs_liste") return d([DEMANDE(7, { livreur_id: BIZ, nom_livreur: "Codjo" }),
      DEMANDE(8, { livreur_id: BIZ, nom_livreur: "Codjo" })]);
    if (c === "rpc/reversements_vendeurs_liste") return d([DEMANDE(7, { vendeur_id: "v1", nom_vendeur: "AZERTY" })]);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("commandes")) return d([]);
    if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha", actif: true, devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html" + adresse, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(3000);
  return { page, ctx, erreurs };
}
const toasts = (page) => page.evaluate(() => (window.__toasts || []).join(" | "));
const marque = (page, sel) => page.evaluate((s) => {
  const el = document.querySelector(s);
  return el ? el.classList.contains("vise") : null;
}, sel);

titre("1. Nouvelle course : CETTE course, sous les yeux");
{
  const { page, ctx, erreurs } = await ouvrir(BIZ, "#/livraisons/cmd_s");
  ok(await marque(page, '.lv-course[data-commande="cmd_s"]') === true, "la carte de la course cmd_s est marquée");
  ok(await marque(page, '.lv-course[data-commande="cmd_r"]') === false, "l'autre course ne l'est pas");
  const vue = await page.evaluate(() => {
    const r = document.querySelector('.lv-course[data-commande="cmd_s"]').getBoundingClientRect();
    return r.top < innerHeight && r.bottom > 0;
  });
  ok(vue, "elle est amenée à l'écran");
  ok(await page.evaluate(() => location.hash) === "#/livraisons", "l'adresse redevient « #/livraisons »");
  await page.evaluate(() => { location.hash = "#/livraisons/cmd_prise"; });
  await page.waitForTimeout(1500);
  ok(/n'est plus à prendre/.test(await toasts(page)), "une course déjà prise : « Cette course n'est plus à prendre »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("2. Demande de reversement : CETTE demande");
{
  const { page, ctx, erreurs } = await ouvrir(SUP, "#/reversements/livreur-7");
  ok(await marque(page, '[data-cle="livreur-7"]') === true, "la demande du livreur n° 7 est marquée");
  ok(await marque(page, '[data-cle="vendeur-7"]') === false, "pas celle du vendeur qui porte le même numéro");
  ok(await marque(page, '[data-cle="livreur-8"]') === false, "ni l'autre demande du livreur");
  ok(await page.evaluate(() => location.hash) === "#/reversements", "l'adresse redevient « #/reversements »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("3. Compte à valider : sa fiche s'ouvre");
{
  const { page, ctx, erreurs } = await ouvrir(SUP, "#/comptes/" + MODO);
  const feuille = await page.evaluate(() => {
    const f = document.getElementById("feuille");
    return f && !f.hidden ? (document.getElementById("feuille-titre").innerText + " " + f.innerText) : "";
  });
  ok(/modo\.attente@bizzoo\.bj/.test(feuille), "la fiche du compte à valider est ouverte");
  ok(await page.evaluate(() => location.hash) === "#/comptes", "l'adresse redevient « #/comptes »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("4. L'adresse d'un reçu client : la commande");
{
  const { page, ctx, erreurs } = await ouvrir(SUP, "#/commande/cmd_r");
  ok(await page.evaluate(() => location.hash) === "#/commandes/cmd_r", "« #/commande/cmd_r » mène à « #/commandes/cmd_r »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("5. Plusieurs ruptures : le stock filtré");
{
  const { page, ctx, erreurs } = await ouvrir(CHEF, "#/stock?filtre=rupture");
  ok(await page.evaluate(() => location.hash) === "#/stock?filtre=rupture", "l'écran du stock reste ouvert, filtré");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " ÉCHEC(S)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
