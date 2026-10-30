/* =========================================================
   L'administrateur de BIZZOO, et ce que voit une boutique (3.59.0)
   =========================================================
   La base (supabase/tests/99zzzzz-admin-bizzoo.sql) ouvre à
   l'administrateur de BIZZOO — un administrateur sans boutique — les
   livreurs et les revendeurs. Les écrans :

     1. son accueil mène aux livreurs et aux revendeurs ;
     2. il crée un livreur (par son numéro), pour BIZZOO ou une boutique ;
     3. il crée un revendeur : le compte naît par le numéro, la base pose
        sa demande ; il valide une demande qui a sa position ;
     4. un modérateur de BIZZOO n'entre ni chez les livreurs ni chez les
        revendeurs ;
     5. l'administrateur d'une boutique VOIT ses livreurs — ceux de sa
        boutique et ceux de BIZZOO —, sans rien créer ni modifier ;
     7. (3.63.0) l'administrateur de BIZZOO a le crayon sur TOUS les
        livreurs — mot de passe et suppression compris —, et crée un
        modérateur qui naît INACTIF, « à valider » ;
     8. (3.63.0) le superadministrateur le valide d'un bouton.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-admin-bizzoo.mjs");
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
const jeton = (sub) => {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return b64({ alg: "HS256" }) + "." + b64({ sub }) + ".s";
};

const ADMBZ = "a1110000-0000-0000-0000-000000000001";
const MODBZ = "a2220000-0000-0000-0000-000000000002";
const CHEF = "a3330000-0000-0000-0000-000000000003";
const LIV_A = "a4440000-0000-0000-0000-000000000004";
const LIV_BZ = "a5550000-0000-0000-0000-000000000005";
const NEUF = "a6660000-0000-0000-0000-000000000006";
const SUPER = "a7770000-0000-0000-0000-000000000007";
const PEND = "a8880000-0000-0000-0000-000000000008";
const P = (id, email, role, boutique, extra) => ({ id, email, role, actif: true, peut_modifier_produits: true,
  boutique_id: boutique, nom: "", tel: "0197000000", peut_commandes: true, peut_boutiques: false,
  peut_finances: false, ...(extra || {}) });
const PROFILS = [
  P(ADMBZ, "admin@bizzoo.bj", "administrateur", null),
  P(MODBZ, "modo@bizzoo.bj", "moderateur", null),
  P(CHEF, "chef@alpha.bj", "administrateur", "bou_a"),
  P(LIV_A, "rohim@alpha.bj", "livreur", "bou_a", { nom: "Rohim", tel: "0196000101" }),
  P(LIV_BZ, "", "livreur", null, { nom: "Sèna", tel: "0196000202" }),
  P(SUPER, "patron@bizzoo.bj", "superadministrateur", null),
  P(PEND, "fifame@alpha.bj", "moderateur", "bou_a",
    { nom: "Fifamè", actif: false, a_valider: true, cree_par: ADMBZ, cree_par_nom: "Admin (administrateur)" }),
];
const BOU = [{ id: "bou_a", nom: "Alpha", categorie_id: null, icone: "magasin", couleur: "#0047D9",
  devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }];
const DEMANDE = { id: "r1", nom: "Boutique Sika", email: "", tel: "0161444001", indicatif: "229",
  message: "Accessoires", etat: "en_attente", demande_le: "2026-10-17T08:00:00Z", decide_par: "",
  decide_le: null, motif: "", adresse: "Dantokpa", latitude: 6.35, longitude: 2.43 };

async function ouvrir(moi, hash = "") {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2000 } });
  const page = await ctx.newPage();
  const erreurs = [];
  const note = { signup: [], profils: [], rpc: [], patch: [] };
  page.on("pageerror", (e) => erreurs.push(e.message));
  page.on("dialog", (d) => d.accept());
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: a.t, refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
    navigator.geolocation && Object.defineProperty(navigator, "geolocation", { configurable: true, value: {
      getCurrentPosition: (ok) => ok({ coords: { latitude: 6.36, longitude: 2.41, accuracy: 10 } }) } });
  }, { t: jeton(moi), email: PROFILS.find((p) => p.id === moi).email });
  await page.route("**/auth/v1/**", (route) => {
    const req = route.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/auth\/v1\//, "");
    const corps = corpsDe(req) || {};
    if (c === "signup") {
      note.signup.push(corps);
      return route.fulfill({ status: 200, contentType: "application/json",
        body: JSON.stringify({ id: NEUF, phone: String(corps.phone || "").replace(/\D/g, ""), identities: [{ id: "x" }] }) });
    }
    return route.fulfill({ status: 200, contentType: "application/json", body: "{}" });
  });
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, s = 200) => route.fulfill({ status: s, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) note.rpc.push({ nom: c.slice(4), corps: corpsDe(req) });
    if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    if (c === "rpc/revendeurs") return d([DEMANDE]);
    if (c === "rpc/creer_fiche_revendeur") return d("en_attente");
    if (c === "rpc/valider_revendeur") return d("validee");
    if (c === "rpc/livreurs_boutique") {
      return d([{ id: LIV_A, email: "rohim@alpha.bj", nom: "Rohim", tel: "0196000101", actif: true, bizzoo: false },
                { id: LIV_BZ, email: "", nom: "Sèna", tel: "0196000202", actif: true, bizzoo: true }]);
    }
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("positions_livreurs")) {
      return d([{ profil_id: LIV_A, latitude: 6.36, longitude: 2.41, adresse: "Akpakpa", enregistre_le: "2026-10-16T08:00:00Z" }]);
    }
    if (c.startsWith("profils")) {
      if (req.method() === "POST") { const x = corpsDe(req); note.profils.push(x); return d([x], 201); }
      const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      if (req.method() === "PATCH") {
        note.patch.push({ id, corps: corpsDe(req) });
        return d(PROFILS.filter((p) => p.id === id).map((p) => ({ ...p, ...corpsDe(req) })));
      }
      if (id) return d(PROFILS.filter((p) => p.id === id));
      // Ce que la base rend à chacun (règles de « profils »)
      if (moi === CHEF) return d(PROFILS.filter((p) => p.id === CHEF || p.boutique_id === "bou_a"));
      if (moi === ADMBZ) {
        return d(PROFILS.filter((p) => p.id === ADMBZ || p.role === "livreur" ||
          (p.role === "moderateur" && p.cree_par === ADMBZ)));
      }
      if (moi === SUPER) return d(PROFILS);
      return d(PROFILS.filter((p) => p.id === moi));
    }
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await pause(2200);
  if (hash) { await page.evaluate((h) => { location.hash = h; }, hash); await pause(1500); }
  return { ctx, page, erreurs, note };
}
const texte = (page) => page.evaluate(() => document.getElementById("vue").innerText.replace(/\s+/g, " "));
const ici = (page) => page.evaluate(() => location.hash);
const sansErreur = (o) => ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));

titre("1. L'accueil de l'administrateur de BIZZOO");
{
  const o = await ouvrir(ADMBZ);
  ok(!!(await o.page.$("#ac-livreurs-revendeurs")), "une carte « Livreurs et revendeurs »");
  ok(!!(await o.page.$('#ac-livreurs-revendeurs a[href="#/livreurs"]')) &&
     !!(await o.page.$('#ac-livreurs-revendeurs a[href="#/revendeurs"]')), "elle mène aux deux écrans");
  ok(o.note.rpc.some((r) => r.nom === "revendeurs"), "les demandes en attente sont lues pour lui");
  ok(!!(await o.page.$('#ac-livreurs-revendeurs a[href="#/comptes"]')),
    "(3.63.0) et aux modérateurs qu'il crée");
  sansErreur(o);
  await o.ctx.close();
}

titre("2. Il crée un livreur");
{
  const o = await ouvrir(ADMBZ, "#/livreurs");
  ok(await ici(o.page) === "#/livreurs", "il entre chez les livreurs");
  const t = await texte(o.page);
  ok(/Rohim/.test(t) && /Sèna/.test(t), "il les voit tous");
  await o.page.click("#lv-nouveau");
  await pause(500);
  const f = await o.page.evaluate(() => ({
    actif: !document.querySelector("#nc-boutique").disabled,
    options: [...document.querySelector("#nc-boutique").options].map((x) => x.value),
  }));
  ok(f.actif && f.options.includes("__enseigne") && f.options.includes("bou_a"),
    "il choisit : BIZZOO ou une boutique (" + f.options.join(", ") + ")");
  await o.page.fill("#nc-tel", "01 96 00 03 03");
  await o.page.fill("#nc-mdp", "secret-essai");
  await o.page.fill("#nc-nom", "Bio");
  await o.page.selectOption("#nc-boutique", "bou_a");
  /* (3.72.0) Le nom du compte MoMo d'un livreur, obligatoire. */
  if (await o.page.$("#nc-momo-nom")) await o.page.fill("#nc-momo-nom", "Titulaire MoMo");
  await o.page.click("#nc-creer");
  await pause(1200);
  const s = o.note.signup[0] || {};
  ok(s.phone === "+2290196000303" && s.data && s.data.compte === "equipe", "le compte naît par le numéro");
  const fiche = o.note.profils[0] || {};
  ok(fiche.role === "livreur" && fiche.boutique_id === "bou_a" && fiche.actif === true,
    "sa fiche : livreur de la boutique Alpha");
  sansErreur(o);
  await o.ctx.close();
}

titre("3. Il crée un revendeur et valide une demande");
{
  const o = await ouvrir(ADMBZ, "#/revendeurs");
  ok(await ici(o.page) === "#/revendeurs", "il entre chez les revendeurs");
  await o.page.click("#rv-nouveau");
  await pause(500);
  await o.page.fill("#nr-nom", "Boutique Kpodji");
  await o.page.fill("#nr-tel", "0161555002");
  await o.page.fill("#nr-mdp", "secret-essai");
  await o.page.click("#nr-creer");
  await pause(500);
  ok(!o.note.signup.length && /adresse/.test(await o.page.innerText("#nr-resultat")),
    "sans adresse du commerce, rien ne part");
  await o.page.fill("#nr-commerce", "Téléphones et accessoires");
  await o.page.fill("#nr-adresse", "Missèbo, près du marché");
  await o.page.click("#nr-creer");
  await pause(1500);
  const s = o.note.signup[0] || {};
  ok(s.phone === "+2290161555002" && s.password === "secret-essai" && s.data && s.data.compte === "client" && !s.email,
    "le compte naît par le numéro, comme un client, sans e-mail");
  const f = (o.note.rpc.find((r) => r.nom === "creer_fiche_revendeur") || {}).corps || {};
  ok(f.cible === NEUF && f.nom === "Boutique Kpodji" && f.adresse === "Missèbo, près du marché" &&
     f.message === "Téléphones et accessoires", "la base pose sa demande, avec son commerce et son adresse");
  await o.page.click('[data-valider="r1"]');
  await pause(800);
  const conf = await o.page.$("[data-role=\"ok\"]");
  if (conf) { await conf.click().catch(() => {}); await pause(1000); }
  ok(o.note.rpc.some((r) => r.nom === "valider_revendeur" && r.corps && r.corps.accord === true && r.corps.cible === "r1"),
    "il valide la demande qui a sa position");
  sansErreur(o);
  await o.ctx.close();
}

titre("4. Un modérateur de BIZZOO : ni livreurs, ni revendeurs");
{
  const o = await ouvrir(MODBZ, "#/livreurs");
  ok(await ici(o.page) !== "#/livreurs", "les livreurs lui sont fermés");
  await o.page.evaluate(() => { location.hash = "#/revendeurs"; });
  await pause(1200);
  ok(await ici(o.page) !== "#/revendeurs", "les revendeurs aussi");
  ok(!(await o.page.$("#ac-livreurs-revendeurs")), "et son accueil n'en parle pas");
  await o.ctx.close();
}

titre("5. L'administrateur d'une boutique crée ses livreurs (3.59.0)");
{
  const o = await ouvrir(CHEF, "#/livreurs");
  ok(await ici(o.page) === "#/livreurs", "il entre chez les livreurs");
  const t = await texte(o.page);
  ok(/Rohim/.test(t) && /Sèna/.test(t), "ceux de sa boutique ET ceux de BIZZOO");
  ok(/Position validée/.test(t), "la position du sien");
  ok(/Livreur de BIZZOO : il porte pour toutes les boutiques/.test(t), "celui de BIZZOO est dit tel");
  ok(!!(await o.page.$('.livreur-bloc [data-compte="' + LIV_A + '"]')), "le sien a sa fiche, à modifier");
  ok(!(await o.page.$('.livreur-bloc [data-compte="' + LIV_BZ + '"]')) &&
     !!(await o.page.$('a[href="tel:0196000202"]')), "celui de BIZZOO : à lire et appeler, pas à modifier");
  await o.page.click("#lv-nouveau");
  await pause(500);
  const f = await o.page.evaluate(() => ({
    bloque: document.querySelector("#nc-boutique") ? document.querySelector("#nc-boutique").disabled : true,
    valeur: document.querySelector("#nc-boutique") ? document.querySelector("#nc-boutique").value : "",
    roles: [...document.querySelectorAll("#nc-role option")].map((x) => x.value) }));
  ok(f.bloque && f.valeur === "bou_a" && f.roles.join() === "livreur",
    "« Créer un livreur » : un livreur, pour sa boutique Alpha seulement");
  await o.page.fill("#nc-tel", "01 96 00 04 04");
  await o.page.fill("#nc-mdp", "secret-essai");
  await o.page.fill("#nc-nom", "Kodjo");
  /* (3.72.0) Le nom du compte MoMo d'un livreur, obligatoire. */
  if (await o.page.$("#nc-momo-nom")) await o.page.fill("#nc-momo-nom", "Titulaire MoMo");
  await o.page.click("#nc-creer");
  await pause(1200);
  const fiche = o.note.profils[0] || {};
  ok(fiche.role === "livreur" && fiche.boutique_id === "bou_a", "sa fiche : livreur de la boutique Alpha");
  sansErreur(o);
  await o.ctx.close();
}
{
  const o = await ouvrir(CHEF, "#/comptes");
  await pause(500);
  if (await o.page.$("#cp-nouveau")) {
    await o.page.click("#cp-nouveau");
    await pause(500);
  }
  const roles = await o.page.evaluate(() => [...document.querySelectorAll("#nc-role option")].map((x) => x.value));
  ok(!roles.includes("administrateur") && !roles.includes("superadministrateur"),
    "il ne crée pas d'administrateur (" + roles.join(", ") + ")");
  await o.ctx.close();
}

titre("6. L'administrateur d'une boutique crée un revendeur ; BIZZOO valide");
{
  const o = await ouvrir(CHEF);
  ok(!!(await o.page.$('#ac-livreurs-revendeurs a[href="#/revendeurs"]')) &&
     !!(await o.page.$('#ac-livreurs-revendeurs a[href="#/livreurs"]')), "son accueil mène aux livreurs et aux revendeurs");
  await o.page.evaluate(() => { location.hash = "#/revendeurs"; });
  await pause(1500);
  ok(await ici(o.page) === "#/revendeurs" && !!(await o.page.$("#rv-boutique")), "il entre : « Créer un revendeur »");
  ok(!o.note.rpc.some((r) => r.nom === "revendeurs") && !(await o.page.$("[data-valider]")),
    "ni la liste des demandes, ni « Valider » : c'est à BIZZOO");
  await o.page.click("#rv-nouveau");
  await pause(500);
  await o.page.fill("#nr-nom", "Boutique Azon");
  await o.page.fill("#nr-tel", "0161555003");
  await o.page.fill("#nr-mdp", "secret-essai");
  await o.page.fill("#nr-adresse", "Ganhi, face à la banque");
  await o.page.click("#nr-creer");
  await pause(1500);
  ok(o.note.rpc.some((r) => r.nom === "creer_fiche_revendeur" && r.corps && r.corps.nom === "Boutique Azon"),
    "creer_fiche_revendeur : la demande part, en attente");
  sansErreur(o);
  await o.ctx.close();
}

titre("7. L'administrateur de BIZZOO : ses livreurs, et un modérateur à valider (3.63.0)");
{
  const o = await ouvrir(ADMBZ, "#/livreurs");
  ok(!!(await o.page.$('.livreur-bloc [data-compte="' + LIV_A + '"]')) &&
     !!(await o.page.$('.livreur-bloc [data-compte="' + LIV_BZ + '"]')),
    "le crayon sur chaque livreur — d'une boutique comme de BIZZOO");
  await o.page.click('.livreur-bloc [data-compte="' + LIV_BZ + '"]');
  await pause(600);
  ok(!!(await o.page.$("#cp-mdp-changer")) && !!(await o.page.$("#cp-supprimer")) &&
     !!(await o.page.$("#cp-enregistrer")),
    "sa fiche : enregistrer, redonner un mot de passe, supprimer");
  await o.page.fill("#cp-nom", "Sèna D.");
  await o.page.click("#cp-enregistrer");
  await pause(1000);
  ok(o.note.patch.some((x) => x.id === LIV_BZ && x.corps && x.corps.nom === "Sèna D."), "il le renomme");
  await o.page.evaluate(() => { location.hash = "#/comptes"; });
  await pause(1500);
  ok(await ici(o.page) === "#/comptes", "il entre dans Comptes");
  const t = await texte(o.page);
  ok(/Fifamè/.test(t) && /à valider par le superadministrateur/.test(t),
    "il y voit le modérateur qu'il a créé, « à valider »");
  ok(!!(await o.page.$('[data-compte="' + PEND + '"]')), "et peut le retoucher tant qu'il attend");
  await o.page.click('[data-compte="' + PEND + '"]');
  await pause(600);
  ok(!(await o.page.$("#cp-actif")) && /En attente de validation/.test(await o.page.innerText("body")),
    "sa fiche : pas d'interrupteur « actif », l'attente est dite");
  await o.page.evaluate(() => UI.fermerFeuille());
  await pause(400);
  await o.page.click("#cp-nouveau");
  await pause(600);
  const f = await o.page.evaluate(() => ({
    roles: [...document.querySelectorAll("#nc-role option")].map((x) => x.value),
    boutiques: [...document.querySelector("#nc-boutique").options].map((x) => x.value),
    libre: !document.querySelector("#nc-boutique").disabled }));
  ok(f.roles.join() === "moderateur", "il crée un modérateur, et rien d'autre (" + f.roles.join(", ") + ")");
  ok(f.libre && f.boutiques.includes("bou_a") && f.boutiques.includes("__enseigne"),
    "pour une boutique ou pour BIZZOO");
  await o.page.fill("#nc-email", "kossi@alpha.bj");
  await o.page.fill("#nc-mdp", "secret-essai");
  await o.page.fill("#nc-nom", "Kossi");
  await o.page.fill("#nc-tel", "0197112233");
  await o.page.selectOption("#nc-boutique", "bou_a");
  /* (3.72.0) Le nom du compte MoMo d'un livreur, obligatoire. */
  if (await o.page.$("#nc-momo-nom")) await o.page.fill("#nc-momo-nom", "Titulaire MoMo");
  await o.page.click("#nc-creer");
  await pause(1500);
  const fiche = o.note.profils[0] || {};
  ok(fiche.role === "moderateur" && fiche.boutique_id === "bou_a" && fiche.actif === false,
    "sa fiche part INACTIVE : modérateur d'Alpha, à valider");
  sansErreur(o);
  await o.ctx.close();
}

titre("8. Le superadministrateur valide (3.63.0)");
{
  const o = await ouvrir(SUPER, "#/comptes");
  const t = await texte(o.page);
  ok(/À valider \(1\)/.test(t) && /Fifamè/.test(t), "« À valider (1) », en tête");
  await o.page.click('[data-valider="' + PEND + '"]');
  await pause(1200);
  ok(o.note.patch.some((x) => x.id === PEND && x.corps && x.corps.actif === true),
    "« Valider » l'active");
  sansErreur(o);
  await o.ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec." : "\nTous les constats sont bons.");
process.exit(echecs ? 1 : 0);
