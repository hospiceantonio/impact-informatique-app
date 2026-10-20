/* =========================================================
   Les livreurs entrent par leur numéro (3.59.0)
   =========================================================
   Dans BIZZOO Admin :

     1. « Créer un livreur » demande son NUMÉRO, un mot de passe, son
        nom ; l'e-mail est facultatif. Le compte naît par le numéro,
        avec « compte: equipe » — sans quoi la base le prendrait pour un
        acheteur —, et sa fiche garde l'e-mail noté ;
     2. le livreur entre avec son numéro et son mot de passe, PUIS un
        code reçu par SMS. Mauvais mot de passe : aucun code ne part. La
        session du mot de passe est fermée, seule celle du code reste ;
        l'e-mail de sa fiche devient sa porte de secours ;
     3. un numéro pas encore confirmé (compte tout neuf) redemande son
        code de confirmation, sans refus ;
     4. l'e-mail et le mot de passe restent la porte de l'équipe : aucun
        code Supabase.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-connexion-telephone.mjs");
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
const jeton = (charge) => {
  const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return b64({ alg: "HS256" }) + "." + b64(charge) + ".s";
};
const charge = (j) => {
  try { return JSON.parse(Buffer.from((j || "").split(".")[1] || "", "base64").toString()); }
  catch (_) { return {}; }
};

const SUPER = "11110000-0000-0000-0000-000000000001";
const LIVREUR = "55550000-0000-0000-0000-000000000005";
const NEUF = "66660000-0000-0000-0000-000000000006";
const P = (id, email, role, extra) => ({ id, email, role, actif: true, peut_modifier_produits: true,
  boutique_id: role === "superadministrateur" ? null : "bou_a", nom: "", tel: "0197000000",
  ...(extra || {}) });
const PROFILS = [
  P(SUPER, "chef@bizzoo.bj", "superadministrateur"),
  P(LIVREUR, "kossi@essai.bj", "livreur", { nom: "Kossi", tel: "0196000111" }),
];
const BOU = [{ id: "bou_a", nom: "Alpha", categorie_id: null, icone: "magasin", couleur: "#0047D9",
  devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }];

async function ouvrir({ moi = null, hash = "", nonConfirme = false } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1600 } });
  const page = await ctx.newPage();
  const erreurs = [];
  const note = { signup: [], token: [], otp: [], resend: [], verify: [], logout: [], put: [], profils: [] };
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    if (a.t) {
      localStorage.setItem("impact-session", JSON.stringify({
        access_token: a.t, refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
    } else {
      localStorage.removeItem("impact-session");
    }
  }, { t: moi ? jeton({ sub: moi }) : "", email: moi ? PROFILS.find((p) => p.id === moi).email : "" });

  let connecte = moi;
  await page.route("**/auth/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/auth\/v1\//, "");
    const corps = corpsDe(req) || {};
    const d = (x, s = 200) => route.fulfill({ status: s, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "signup") {
      note.signup.push({ corps, auth: req.headers()["authorization"] || "" });
      return d({ id: NEUF, phone: String(corps.phone || "").replace(/\D/g, ""), identities: [{ id: "x" }] });
    }
    if (c.startsWith("token") && corps.phone) {
      note.token.push(corps);
      if (corps.password !== "secret-essai") {
        return d({ code: 400, error_code: "invalid_credentials", msg: "Invalid login credentials" }, 400);
      }
      if (nonConfirme) return d({ error: "invalid_grant", error_description: "Phone not confirmed" }, 400);
      return d({ access_token: jeton({ sub: LIVREUR, session_id: "mdp", amr: [{ method: "password" }] }),
        refresh_token: "rm", expires_in: 3600, user: { id: LIVREUR, phone: "2290196000111", email: "" } });
    }
    if (c.startsWith("token")) {
      note.token.push(corps);
      connecte = SUPER;
      return d({ access_token: jeton({ sub: SUPER }), refresh_token: "re", expires_in: 3600,
        user: { id: SUPER, email: corps.email } });
    }
    if (c === "otp") { note.otp.push(corps); return d({}); }
    if (c === "resend") { note.resend.push(corps); return d({}); }
    if (c === "verify") {
      note.verify.push(corps);
      connecte = LIVREUR;
      return d({ access_token: jeton({ sub: LIVREUR, session_id: "code", phone: "2290196000111",
        amr: [{ method: "otp" }] }), refresh_token: "rc", expires_in: 3600,
        user: { id: LIVREUR, phone: "2290196000111", email: "" } });
    }
    if (c === "logout") {
      note.logout.push({ portee: u.searchParams.get("scope") || "", auth: req.headers()["authorization"] || "" });
      return route.fulfill({ status: 204, body: "" });
    }
    if (c === "user" && req.method() === "PUT") {
      note.put.push({ corps, auth: req.headers()["authorization"] || "" });
      return d({ id: LIVREUR, email: corps.email || "" });
    }
    return d({});
  });
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, s = 200) => route.fulfill({ status: s, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/etat_connexion") {
      return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    }
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("positions_livreurs")) {
      return d([{ profil_id: LIVREUR, latitude: 6.36, longitude: 2.41, adresse: "Akpakpa",
        enregistre_le: "2026-10-16T08:00:00Z" }]);
    }
    if (c.startsWith("profils")) {
      if (req.method() === "POST") {
        const corps = corpsDe(req);
        note.profils.push(corps);
        return d([corps], 201);
      }
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
  return { ctx, page, erreurs, note, qui: () => connecte };
}
const texte = (page) => page.evaluate(() => document.body.innerText.replace(/\s+/g, " "));
const sansErreur = (o) => ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));

titre("1. « Créer un livreur » : son numéro, un mot de passe, l'e-mail facultatif");
{
  const o = await ouvrir({ moi: SUPER, hash: "#/livreurs" });
  await o.page.click("#lv-nouveau");
  await pause(500);
  const ordre = await o.page.evaluate(() => [...document.querySelectorAll(".feuille input")].map((i) => i.id));
  ok(ordre[0] === "nc-tel", "le numéro vient en premier (" + ordre.join(", ") + ")");
  ok(/facultatif/.test(await texte(o.page)), "l'e-mail est dit facultatif");

  await o.page.fill("#nc-tel", "01 96 00 02 22");
  await o.page.fill("#nc-mdp", "secret-essai");
  await o.page.fill("#nc-nom", "Bio");
  await o.page.fill("#nc-email", "pas-une-adresse");
  await o.page.click("#nc-creer");
  await pause(600);
  ok(!o.note.signup.length && /adresse email valide/.test(await texte(o.page)),
    "un e-mail mal formé, même facultatif, est refusé");

  await o.page.fill("#nc-email", "");
  await o.page.click("#nc-creer");
  await pause(1200);
  const s = (o.note.signup[0] || {}).corps || {};
  ok(s.phone === "+2290196000222" && s.password === "secret-essai" && !s.email,
    "le compte naît par le numéro, au format de GoTrue — sans e-mail (" + s.phone + ")");
  ok(s.data && s.data.compte === "equipe" && s.data.nom === "Bio",
    "avec « compte: equipe » et son nom : la base lui pose sa fiche d'équipe");
  const f = o.note.profils[0] || {};
  ok(f.id === NEUF && f.role === "livreur" && f.tel === "01 96 00 02 22" && f.email === "" && f.actif === true,
    "sa fiche : livreur, actif, son numéro, sans e-mail");
  sansErreur(o);
  await o.ctx.close();
}
{
  const o = await ouvrir({ moi: SUPER, hash: "#/livreurs" });
  await o.page.click("#lv-nouveau");
  await pause(500);
  await o.page.fill("#nc-tel", "0196000333");
  await o.page.fill("#nc-mdp", "secret-essai");
  await o.page.fill("#nc-email", "Bio@Essai.bj");
  await o.page.click("#nc-creer");
  await pause(1200);
  ok((o.note.profils[0] || {}).email === "bio@essai.bj" && !((o.note.signup[0] || {}).corps || {}).email,
    "avec un e-mail : il est noté sur sa fiche — le compte, lui, naît par le numéro");
  await o.ctx.close();
}
{
  const o = await ouvrir({ moi: SUPER, hash: "#/comptes" });
  await o.page.click("#cp-nouveau");
  await pause(500);
  const ordre = await o.page.evaluate(() => [...document.querySelectorAll(".feuille input")].map((i) => i.id));
  ok(ordre[0] === "nc-email", "le reste de l'équipe garde l'e-mail en premier");
  await o.ctx.close();
}

titre("2. Le livreur entre : numéro et mot de passe, sans code");
{
  const o = await ouvrir();
  ok(await o.page.$("#cx-email") && /numéro/.test(await texte(o.page)),
    "l'écran de connexion accepte e-mail OU numéro");
  await o.page.fill("#cx-email", "01 96 00 01 11");
  await o.page.fill("#cx-mdp", "mauvais");
  await o.page.click("#cx-connecter");
  await pause(800);
  ok(o.note.token.length === 1 && !o.note.otp.length &&
     /Numéro ou mot de passe incorrect/.test(await texte(o.page)),
    "mauvais mot de passe : refusé, et aucun code ne part");
  const t0 = o.note.token[0] || {};
  ok(t0.phone === "+2290196000111" && !t0.email, "le mot de passe se vérifie avec le numéro (" + t0.phone + ")");

  await o.page.fill("#cx-mdp", "secret-essai");
  await o.page.click("#cx-connecter");
  await pause(900);
  /* (3.59.0) Numéro déjà confirmé : le mot de passe suffit, plus de
     code à chaque connexion. */
  ok(!o.note.otp.length && !o.note.verify.length, "le mot de passe juste : aucun code ne part");
  ok(!(await o.page.$("#cx-code-tel")), "pas d'écran de code");
  const s = await o.page.evaluate(() => JSON.parse(localStorage.getItem("impact-session") || "null"));
  ok(!!s && charge(s.access_token).session_id === "mdp", "la session du mot de passe est gardée");
  ok(!o.note.logout.length, "et elle n'est pas fermée");
  ok(!(await o.page.$("#cx-code-tel")) && !(await o.page.$("#cx-connecter")),
    "il entre dans l'application");
  sansErreur(o);
  await o.ctx.close();
}

titre("3. Compte tout neuf : le numéro pas encore confirmé");
{
  const o = await ouvrir({ nonConfirme: true });
  await o.page.fill("#cx-email", "0196000111");
  await o.page.fill("#cx-mdp", "secret-essai");
  await o.page.click("#cx-connecter");
  await pause(900);
  ok(!o.note.otp.length && (o.note.resend[0] || {}).type === "sms" && !!(await o.page.$("#cx-code-tel")),
    "le code de confirmation est redemandé — pas de refus");
  await o.page.click("#cx-code-renvoyer");
  await pause(500);
  ok(o.note.resend.length === 2, "« Renvoyer un code » redemande le même");
  sansErreur(o);
  await o.ctx.close();
}

titre("4. L'équipe garde l'e-mail et le mot de passe");
{
  const o = await ouvrir();
  await o.page.fill("#cx-email", "chef@bizzoo.bj");
  await o.page.fill("#cx-mdp", "secret-essai");
  await o.page.click("#cx-connecter");
  await pause(1800);
  const t = o.note.token[0] || {};
  ok(t.email === "chef@bizzoo.bj" && !t.phone && !o.note.otp.length && !o.note.resend.length,
    "e-mail et mot de passe : aucun code Supabase");
  ok(!(await o.page.$("#cx-connecter")), "il entre");
  sansErreur(o);
  await o.ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec." : "\nTous les constats sont bons.");
process.exit(echecs ? 1 : 0);
