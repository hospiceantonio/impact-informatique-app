/* =========================================================
   Les livreurs à part, et la position qui valide les comptes
   =========================================================
   La base refuse de confier une course à un livreur sans position, et
   de valider un revendeur sans position (supabase/tests/99zz-positions-
   comptes.sql). Les écrans :

     1. COMPTES : l'équipe, SANS les livreurs ; une carte mène à eux ;
        « Créer un compte » ne propose plus « Livreur » ;
     2. LIVREURS : leur liste, qui a validé sa position et qui non, et
        leur propre bouton « Créer un livreur » ;
     3. LE LIVREUR sans position est arrêté sur « Validez votre
        compte » : adresse, puis position du téléphone ; ensuite, ses
        courses. Avec sa position, il y va droit. Une base d'avant ne
        bloque personne ;
     4. LE REVENDEUR : sa demande ne part pas sans la position du
        téléphone ; en attente sans position, son compte le lui dit ;
     5. L'ADMIN des revendeurs : « Valider » est désactivé sans position.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-positions-comptes.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const corpsDe = (req) => { try { return req.postDataJSON(); } catch (_) { return null; } };
const jeton = (moi) => {
  const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return b64({ alg: "HS256" }) + "." + b64({ sub: moi }) + ".s";
};
const GEO = () => {
  Object.defineProperty(navigator, "geolocation", { configurable: true, value: {
    getCurrentPosition: (ok) => setTimeout(() =>
      ok({ coords: { latitude: 6.3654, longitude: 2.4183, accuracy: 12 } }), 30) } });
};

const SUPER = "11110000-0000-0000-0000-000000000001";
const MODO = "22220000-0000-0000-0000-000000000002";
const LIV_OK = "33330000-0000-0000-0000-000000000003";
const LIV_NON = "44440000-0000-0000-0000-000000000004";
const P = (id, email, role, extra) => ({ id, email, role, actif: true, peut_modifier_produits: true,
  boutique_id: role === "superadministrateur" ? null : "bou_a", nom: "", tel: "0197000000",
  ...(extra || {}) });
const PROFILS = [
  P(SUPER, "chef@bizzoo.bj", "superadministrateur"),
  P(MODO, "modo@alpha.bj", "moderateur", { nom: "Awa" }),
  P(LIV_OK, "rohim@alpha.bj", "livreur", { nom: "Rohim" }),
  P(LIV_NON, "codjo@alpha.bj", "livreur", { nom: "Codjo" }),
];
const BOU = [{ id: "bou_a", nom: "Alpha", categorie_id: null, icone: "magasin", couleur: "#0047D9",
  devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }];

async function ouvrirAdmin(moi, { hash = "", positions = { [LIV_OK]: true }, ancienne = false,
                                  revendeurs = [] } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1600 } });
  const page = await ctx.newPage();
  const erreurs = [];
  const appels = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: a.t, refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
  }, { t: jeton(moi), email: PROFILS.find((p) => p.id === moi).email });
  await page.addInitScript(GEO);
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, s = 200) => route.fulfill({ status: s, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) appels.push({ nom: c.slice(4), corps: corpsDe(req) });
    if (c === "rpc/enregistrer_ma_position") { positions[moi] = true; return d({ ok: true }); }
    if (c === "rpc/revendeurs") return d(revendeurs);
    if (c === "rpc/mes_livraisons") return d([]);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("positions_livreurs")) {
      if (ancienne) return d({ code: "42P01", message: "relation \"public.positions_livreurs\" does not exist" }, 404);
      const voulu = (u.searchParams.get("profil_id") || "").replace(/^eq\./, "");
      return d(Object.keys(positions).filter((id) => positions[id] && (!voulu || id === voulu))
        .map((id) => ({ profil_id: id, latitude: 6.36, longitude: 2.41, adresse: "Akpakpa",
          enregistre_le: "2026-10-16T08:00:00Z" })));
    }
    if (c.startsWith("profils")) {
      const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      return d(id ? PROFILS.filter((p) => p.id === id) : PROFILS);
    }
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await pause(2000);
  if (hash) { await page.evaluate((h) => { location.hash = h; }, hash); await pause(1500); }
  return { ctx, page, erreurs, appels };
}
const texte = (page) => page.evaluate(() => document.getElementById("vue").innerText.replace(/\s+/g, " "));

titre("1. Comptes : l'équipe, sans les livreurs");
{
  const o = await ouvrirAdmin(SUPER, { hash: "#/comptes" });
  const t = await texte(o.page);
  ok(/Awa/.test(t) && !/Rohim/.test(t) && !/Codjo/.test(t), "la liste de l'équipe ne montre plus les livreurs");
  ok(/Les livreurs \(2\)/.test(t) && !!(await o.page.$('a[href="#/livreurs"]')),
    "une carte « Les livreurs (2) » mène à leur écran");
  await o.page.click("#cp-nouveau");
  await pause(500);
  const rangs = await o.page.evaluate(() => [...document.querySelector("#nc-role").options].map((x) => x.value));
  ok(!rangs.includes("livreur"), "« Créer un compte » ne propose plus « Livreur » (" + rangs.join(", ") + ")");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("2. Livreurs : leur liste, leur position, leur bouton");
{
  const o = await ouvrirAdmin(SUPER, { hash: "#/livreurs" });
  const t = await texte(o.page);
  ok(/Rohim/.test(t) && /Codjo/.test(t) && !/Awa/.test(t), "seulement les livreurs");
  const blocs = await o.page.evaluate(() => [...document.querySelectorAll(".livreur-bloc")]
    .map((b) => b.innerText.replace(/\s+/g, " ")));
  ok(blocs.some((b) => /Rohim/.test(b) && /Position validée/.test(b) && /voir sur la carte/.test(b)),
    "Rohim : « Position validée », avec la carte");
  ok(blocs.some((b) => /Codjo/.test(b) && /pas encore validée/.test(b)), "Codjo : « Position pas encore validée »");
  ok(/1 sur 2 l'ont fait/.test(t), "« 1 sur 2 l'ont fait »");
  await o.page.click("#lv-nouveau");
  await pause(500);
  const f = await o.page.evaluate(() => ({
    titre: (document.querySelector(".feuille-titre, .feuille h2, .feuille header") || {}).innerText || document.body.innerText,
    role: document.querySelector("#nc-role").value,
    cache: document.querySelector("#nc-role").closest(".champ").hidden,
  }));
  ok(/Nouveau livreur/.test(f.titre) && f.role === "livreur" && f.cache,
    "« Créer un livreur » : le rang est fixé à livreur, sans menu");
  /* (3.72.0) Le nom du compte MoMo, obligatoire à la création. */
  ok(!!(await o.page.$("#nc-momo-nom")), "(3.72.0) le formulaire demande le « Nom du compte MoMo »");
  await o.page.fill("#nc-tel", "0197123456");
  await o.page.fill("#nc-mdp", "secret123");
  await o.page.click("#nc-creer");
  await pause(400);
  ok(/nom du compte MoMo/.test(await o.page.evaluate(() => document.body.innerText)) &&
     !!(await o.page.$("#nc-momo-nom")),
    "(3.72.0) sans lui, rien ne part : on le demande");
  await o.page.evaluate(() => UI.fermerFeuille());
  await o.page.click('[data-compte="' + LIV_OK + '"]');
  await pause(500);
  const rangsFiche = await o.page.evaluate(() => [...document.querySelector("#cp-role").options].map((x) => x.value));
  ok(rangsFiche.length === 1 && rangsFiche[0] === "livreur", "la fiche d'un livreur le garde livreur");
  await o.ctx.close();
}

titre("3. Le livreur valide son compte par sa position");
{
  const o = await ouvrirAdmin(LIV_NON, { positions: {} });
  let t = await texte(o.page);
  ok(/Enregistrez votre position/.test(t) && !!(await o.page.$("#vp-activer")),
    "sans position : arrêté sur « Validez votre compte »");
  await o.page.evaluate(() => { location.hash = "#/livraisons"; });
  await pause(1200);
  ok(!!(await o.page.$("#vp-activer")), "et ses courses ne s'ouvrent pas avant");
  await o.page.click("#vp-activer");
  await pause(300);
  ok(!o.appels.some((a) => a.nom === "enregistrer_ma_position") && /votre adresse/.test(await texte(o.page)),
    "sans adresse : rien ne part");
  await o.page.fill("#vp-adresse", "Akpakpa, face au marché");
  await o.page.click("#vp-activer");
  await pause(1500);
  const a = o.appels.find((x) => x.nom === "enregistrer_ma_position");
  ok(a && a.corps.lat === 6.3654 && a.corps.lng === 2.4183 && a.corps.adresse === "Akpakpa, face au marché",
    "la position du téléphone et l'adresse partent (" + JSON.stringify(a && a.corps) + ")");
  const hash = await o.page.evaluate(() => location.hash);
  ok(hash === "#/livraisons" && !(await o.page.$("#vp-activer")), "puis il arrive sur ses courses (" + hash + ")");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}
{
  const o = await ouvrirAdmin(LIV_OK);
  ok(!(await o.page.$("#vp-activer")) && (await o.page.evaluate(() => location.hash)) === "#/livraisons",
    "avec sa position : droit à ses courses");
  await o.ctx.close();
  const vieille = await ouvrirAdmin(LIV_NON, { positions: {}, ancienne: true });
  ok(!(await vieille.page.$("#vp-activer")), "une base d'avant ne bloque personne");
  await vieille.ctx.close();
}

titre("5. L'admin des revendeurs : pas de validation sans position");
{
  const R = (id, nom, extra) => ({ id, nom, email: nom.toLowerCase() + "@essai.bj", tel: "97000001",
    indicatif: "229", message: "Boutique", etat: "en_attente", demande_le: "2026-10-16T08:00:00Z",
    decide_par: "", decide_le: null, motif: "", adresse: "", latitude: null, longitude: null, ...(extra || {}) });
  const o = await ouvrirAdmin(SUPER, { hash: "#/revendeurs", revendeurs: [
    R("r1", "Sans", {}),
    R("r2", "Avec", { adresse: "Dantokpa", latitude: 6.35, longitude: 2.43 }),
  ] });
  const etat = await o.page.evaluate(() => ({
    sans: document.querySelector('[data-valider="r1"]')?.disabled,
    avec: document.querySelector('[data-valider="r2"]')?.disabled,
    texte: document.body.innerText,
    carte: document.querySelector('.rv-carte[data-compte="r2"] a[href*="maps"]')?.href || "",
  }));
  ok(etat.sans === true && /Position pas encore validée/.test(etat.texte),
    "sans position : « Valider » désactivé, et l'écran dit pourquoi");
  ok(etat.avec === false && /6\.35,2\.43/.test(etat.carte),
    "avec sa position : « Valider » possible, et la carte s'ouvre au bon endroit");
  await o.ctx.close();
}

/* ---------- Le client revendeur ---------- */
const CLIENT = "55550000-0000-0000-0000-000000000005";
async function ouvrirClient(fiche) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2400 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  const patchs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((t) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.setItem("bizzoo-session", JSON.stringify({
      access_token: t, refresh_token: "r", expire_a: Date.now() + 3600000, email: "awa@essai.bj" }));
    window.__toasts = [];
    document.addEventListener("DOMContentLoaded", () => {
      const zone = document.querySelector("#toasts");
      if (zone) new MutationObserver(() => window.__toasts.push(zone.innerText)).observe(zone, { childList: true, subtree: true });
    });
  }, jeton(CLIENT));
  await page.addInitScript(GEO);
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json",
    body: JSON.stringify({ id: CLIENT, email: "awa@essai.bj", phone: "22997000005",
      phone_confirmed_at: "2026-10-16T08:00:00Z", external: { email: true, phone: true } }) }));
  await page.route("**/realtime/**", (r) => r.abort());
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("clients")) {
      if (req.method() === "PATCH") {
        const corps = corpsDe(req) || {};
        patchs.push(corps);
        Object.assign(fiche, corps);
        if (corps.type_compte === "revendeur") fiche.revendeur_etat = "en_attente";
        return d([fiche]);
      }
      return d([fiche]);
    }
    if (c.startsWith("boutiques")) return d([]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("rpc/")) return d(null);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html#/compte", { waitUntil: "domcontentloaded" });
  await pause(2500);
  return { ctx, page, erreurs, patchs };
}
const fiche = (extra) => ({ id: CLIENT, nom: "Awa", tel: "97000005", indicatif: "229", tel_verifie: true,
  adresse: "", type_compte: "client", revendeur_etat: "aucune", revendeur_message: "",
  revendeur_adresse: "", revendeur_latitude: null, revendeur_longitude: null, ...(extra || {}) });

titre("4. Le revendeur : pas de demande sans la position du téléphone");
{
  const o = await ouvrirClient(fiche());
  ok(!(await o.page.$("#cp-rv-pos-lien")), "plus de « lien de carte » à coller : la géolocalisation seule");
  await o.page.fill("#cp-rv-message", "Boutique Awa, pagnes");
  await o.page.fill("#cp-rv-pos-adresse", "Dantokpa, allée des tissus");
  await o.page.click("#cp-rv-demander");
  await pause(400);
  ok(!o.patchs.some((p) => p.type_compte === "revendeur") &&
     (await o.page.evaluate(() => window.__toasts.join(" "))).includes("Activez votre position"),
    "adresse sans position : la demande ne part pas, et l'écran dit quoi faire");
  await o.page.click("#cp-rv-pos-relever");
  await pause(400);
  await o.page.click("#cp-rv-demander");
  await pause(1200);
  const demande = o.patchs.find((p) => p.type_compte === "revendeur") || {};
  ok(demande.revendeur_latitude === 6.3654 && demande.revendeur_longitude === 2.4183 &&
     demande.revendeur_adresse === "Dantokpa, allée des tissus",
    "avec la position du téléphone : la demande part, position et adresse comprises");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}
{
  const o = await ouvrirClient(fiche({ type_compte: "revendeur", revendeur_etat: "en_attente",
    revendeur_message: "Boutique", revendeur_adresse: "Dantokpa" }));
  const r = await o.page.evaluate(() => {
    const c = document.getElementById("cp-ou");
    return c ? { requis: c.classList.contains("cp-ou-requis"), texte: c.innerText,
      ouvert: !document.getElementById("cp-ou-edition").hidden } : null;
  });
  ok(r && r.requis && /Validez votre compte/.test(r.texte) && r.ouvert,
    "en attente sans position : « Validez votre compte : votre position », formulaire ouvert");
  await o.page.click("#cp-ou-pos-relever");
  await pause(300);
  await o.page.click("#cp-ou-enregistrer");
  await pause(1200);
  const p = o.patchs.find((x) => "revendeur_latitude" in x) || {};
  ok(p.revendeur_latitude === 6.3654 && p.revendeur_adresse === "Dantokpa",
    "il l'enregistre depuis son compte");
  await o.ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mLes livreurs ont leur écran, et la position valide les comptes ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
