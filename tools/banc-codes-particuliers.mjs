/* =========================================================
   Les codes promo des particuliers : l'écran admin, la carte client
   =========================================================
   CE QU'ON DÉFEND ICI. La base calcule tout (commission à la
   livraison, plafond, solde, retraits : supabase/tests/99x-codes-
   particuliers.sql). Les écrans, eux, doivent :

     1. ADMIN — créer un compte CLIENT (« compte: client », le nom
        complet) puis le code, avec la remise et la commission saisies ;
     2. ADMIN — montrer les retraits à verser, et marquer « versé »
        avec la référence du transfert ;
     3. CLIENT — montrer « Mes gains » au propriétaire d'un code : son
        code, son solde, l'historique ;
     4. CLIENT — envoyer une demande de retrait (montant, numéro,
        réseau) ;
     5. CLIENT — ne RIEN montrer à un compte sans code, ni quand la
        base ne connaît pas encore la question.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-codes-particuliers.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const MOI = "aaaaaaaa-0000-0000-0000-00000000000a";
const NOUVEAU = "bbbbbbbb-0000-0000-0000-00000000000b";
const corpsDe = (req) => { try { return req.postDataJSON(); } catch (_) { return null; } };
const jeton = (moi) => {
  const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return b64({ alg: "HS256" }) + "." + b64({ sub: moi }) + ".s";
};

/* ---------- L'admin ---------- */
async function ouvrirAdmin() {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1400 } });
  const page = await ctx.newPage();
  const erreurs = [];
  const appels = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(({ moi, t }) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: t, refresh_token: "r", expire_a: Date.now() + 3600000, email: "chef@bizzoo.bj" }));
  }, { moi: MOI, t: jeton(MOI) });
  await page.route("**/auth/v1/**", (r) => {
    const u = new URL(r.request().url());
    if (u.pathname.endsWith("/signup")) {
      appels.push({ nom: "signup", corps: corpsDe(r.request()) });
      return r.fulfill({ status: 200, contentType: "application/json",
        body: JSON.stringify({ user: { id: NOUVEAU, email: "afi@exemple.bj", identities: [{}],
          email_confirmed_at: "2026-10-16T10:00:00Z" } }) });
    }
    return r.fulfill({ status: 200, contentType: "application/json", body: "{}" });
  });
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) appels.push({ nom: c.slice(4), corps: corpsDe(req) });
    if (c.startsWith("profils")) return d([{ id: MOI, email: "chef@bizzoo.bj", role: "superadministrateur",
      actif: true, peut_modifier_produits: true, boutique_id: null }]);
    if (c === "rpc/creer_code_parrain") return d("AFI2026");
    if (c === "rpc/parrains_liste") return d([{ code: "RODRIGUE", libelle: "Rodrigue Agbo",
      parrain: NOUVEAU, email: "rodrigue@exemple.bj", remise: 5, commission: 2, actif: true,
      ventes: 3, gagne: 4200, retire: 1000, en_attente: 500, solde: 2700 }]);
    if (c === "rpc/retraits_a_traiter") return d([{ id: 7, code: "RODRIGUE", email: "rodrigue@exemple.bj",
      montant: 500, numero: "0196000000", reseau: "MTN", etat: "demande",
      demande_le: "2026-10-16T09:00:00Z", traite_le: null, reference: "", motif: "" }]);
    if (c === "rpc/traiter_retrait") return d("payee");
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await pause(1500);
  await page.evaluate(() => { location.hash = "#/codes"; });
  await pause(1500);
  return { ctx, page, erreurs, appels };
}

titre("1. L'admin crée le compte, puis le code");
{
  const o = await ouvrirAdmin();
  const texte = await o.page.evaluate(() => document.getElementById("cd-particuliers")?.innerText || "");
  ok(/Codes des particuliers/i.test(texte) && /RODRIGUE/.test(texte) && /2\s?700/.test(texte.replace(/[\u202f\u00a0]/g, " ")),
    "la section liste les codes, avec le solde de chacun (" + texte.replace(/\s+/g, " ").slice(-160) + ")");
  await o.page.click("#cd-parrain-nouveau");
  await pause(300);
  await o.page.fill("#pa-prenom", "Afi");
  await o.page.fill("#pa-nom", "Houngbo");
  await o.page.fill("#pa-email", "afi@exemple.bj");
  await o.page.fill("#pa-mdp", "un-mot-de-passe-long");
  await o.page.fill("#pa-code", "afi2026");
  await o.page.fill("#pa-remise", "5");
  await o.page.fill("#pa-commission", "2,5");
  await o.page.click("#pa-creer");
  await pause(800);
  const inscription = o.appels.find((a) => a.nom === "signup");
  ok(inscription && inscription.corps.email === "afi@exemple.bj" &&
     inscription.corps.data && inscription.corps.data.compte === "client" &&
     inscription.corps.data.nom === "Afi Houngbo",
    "un compte CLIENT est créé, au nom complet (" + JSON.stringify(inscription && inscription.corps.data) + ")");
  const code = o.appels.find((a) => a.nom === "creer_code_parrain");
  ok(code && code.corps.compte === NOUVEAU && code.corps.le_code === "afi2026" &&
     code.corps.remise === 5 && code.corps.taux === 2.5,
    "puis le code, sur CE compte, avec remise et commission (" + JSON.stringify(code && code.corps) + ")");
  ok(o.appels.findIndex((a) => a.nom === "signup") < o.appels.findIndex((a) => a.nom === "creer_code_parrain"),
    "dans cet ordre : le compte d'abord");

  titre("2. Les retraits à verser");
  const avant = o.appels.length;
  await o.page.click('[data-verser="7"]');
  await pause(300);
  await o.page.fill("#saisie-motif", "MOMO-4471");
  await o.page.click("[data-role=ok]");
  await pause(600);
  const t = o.appels.slice(avant).find((a) => a.nom === "traiter_retrait");
  ok(t && t.corps.cible === 7 && t.corps.payee === true && t.corps.la_reference === "MOMO-4471",
    "« Versé » marque le retrait payé, avec la référence (" + JSON.stringify(t && t.corps) + ")");
  ok(!o.erreurs.length, "aucune erreur dans la page" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

/* ---------- Le client ---------- */
const SOLDE = {
  codes: [{ code: "RODRIGUE", remise: 5, mode: "pourcent", commission: 2, actif: true }],
  gagne: 4200, retire: 1000, en_attente: 500, solde: 2700,
  gains: [{ numero: "BZ-000812", montant: 380, taux: 2, base: 19000, le: "2026-10-15T10:00:00Z" }],
  retraits: [{ id: 3, montant: 500, numero: "0196000000", reseau: "MTN", etat: "demande",
    le: "2026-10-16T09:00:00Z", traite_le: null, motif: "" }],
};

async function ouvrirClient({ reponse = SOLDE, statut = 200 } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2200 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  const appels = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(({ t }) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
    localStorage.setItem("bizzoo-session", JSON.stringify({
      access_token: t, refresh_token: "r", expire_a: Date.now() + 3600000, email: "rodrigue@exemple.bj" }));
  }, { t: jeton(NOUVEAU) });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json",
    body: JSON.stringify({ id: NOUVEAU, email: "rodrigue@exemple.bj", phone: "2290196000000",
      phone_confirmed_at: "2026-10-16T08:00:00Z", external: { email: true, phone: true } }) }));
  await page.route("**/realtime/**", (r) => r.abort());
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, s = 200) => route.fulfill({ status: s, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) appels.push({ nom: c.slice(4), corps: corpsDe(req) });
    if (c === "rpc/mon_solde_parrain") {
      return statut === 200 ? d(reponse)
        : d({ message: "Could not find the function public.mon_solde_parrain" }, statut);
    }
    if (c === "rpc/demander_retrait") return d(9);
    if (c.startsWith("clients")) return d([{ id: NOUVEAU, nom: "Rodrigue Agbo", tel: "0196000000",
      adresse: "", tel_verifie: true, type_compte: "client", revendeur_etat: "aucune" }]);
    if (c.startsWith("boutiques")) return d([]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("rpc/")) return d(null);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html#/compte", { waitUntil: "domcontentloaded" });
  await pause(2500);
  const carte = await page.evaluate(() => {
    const z = document.getElementById("cp-gains");
    return z ? { visible: !z.hidden, texte: z.innerText.replace(/\s+/g, " ") } : null;
  });
  return { ctx, page, erreurs, appels, carte };
}

titre("3. Le propriétaire voit ses gains");
{
  const o = await ouvrirClient();
  ok(o.carte && o.carte.visible, "la carte « Mes gains » est là");
  const t = (o.carte && o.carte.texte) || "";
  ok(/RODRIGUE/.test(t) && /2 700/.test(t), "avec son code et son solde (" + t.slice(0, 90) + "…)");
  ok(/BZ-000812/.test(t) && /\+ 380/.test(t) && /En cours/.test(t),
    "et l'historique : la commission, le retrait en cours");

  titre("4. Il demande un retrait");
  await o.page.click("#cp-retrait-ouvrir");
  await pause(200);
  await o.page.fill("#cp-retrait-montant", "2000");
  await o.page.fill("#cp-retrait-numero", "01 96 00 00 00");
  await o.page.selectOption("#cp-retrait-reseau", "Moov");
  await o.page.click("#cp-retrait-envoyer");
  await pause(800);
  const r = o.appels.find((a) => a.nom === "demander_retrait");
  ok(r && r.corps.montant === 2000 && r.corps.numero === "01 96 00 00 00" && r.corps.reseau === "Moov",
    "la demande part : montant, numéro, réseau (" + JSON.stringify(r && r.corps) + ")");
  const avant = o.appels.filter((a) => a.nom === "demander_retrait").length;
  await o.page.evaluate(() => {
    const b = document.getElementById("cp-retrait-ouvrir"); if (b) b.click();
  });
  await o.page.fill("#cp-retrait-montant", "9000");
  await o.page.click("#cp-retrait-envoyer");
  await pause(300);
  ok(o.appels.filter((a) => a.nom === "demander_retrait").length === avant,
    "plus que le solde : rien ne part");
  ok(!o.erreurs.length, "aucune erreur dans la page" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("5. Pas de code, ou une base d'avant : rien");
{
  const sans = await ouvrirClient({ reponse: null });
  ok(sans.carte && !sans.carte.visible, "un compte sans code ne voit pas la carte");
  await sans.ctx.close();
  const avant = await ouvrirClient({ statut: 404 });
  ok(avant.carte && !avant.carte.visible && !avant.erreurs.length,
    "fonction inconnue de la base : rien, et la page tient");
  await avant.ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mUn code de particulier se crée, rapporte, et se retire ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
