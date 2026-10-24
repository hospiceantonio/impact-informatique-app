/* =========================================================
   Les notifications push de l'équipe (3.65.0) — côté écran
   =========================================================
   La base et la fonction Edge ont leurs essais
   (supabase/tests/99zzz…-notifications-push.sql, tools/eprouver-push.sh).
   Ce banc regarde BIZZOO Admin dans sa coquille Android (pont simulé) :

     1. connecté, l'application déclare le jeton du téléphone à la base —
        même quand Firebase ne le donne qu'après quelques secondes ;
     2. à la déconnexion, elle le retire AVANT de rendre la session ;
     3. dans un navigateur (pas de pont), rien ne part ;
     4. une base d'avant les notifications push ne casse rien.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-push-equipe.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const LIVREUR = "cccccccc-2222-2222-2222-222222222222";
const PROFIL = { id: LIVREUR, email: "pelagie@bizzoo.bj", nom: "Pélagie", role: "livreur", actif: true,
  peut_modifier_produits: true, boutique_id: null };
const JETON = "jeton-firebase-du-telephone-0123456789";

async function ouvrir({ pont = true, retardJeton = 0, baseAncienne = false } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1400 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    const b64 = (o) => btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: a.moi }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
    if (a.pont) {
      /* Le pont de la coquille Android : Firebase donne le jeton quand il veut. */
      const debut = Date.now();
      window.AndroidPont = { jetonPush: () => (Date.now() - debut >= a.retard ? a.jeton : "") };
    }
  }, { moi: LIVREUR, email: PROFIL.email, pont, retard: retardJeton, jeton: JETON });
  const serveur = { appels: [], auth: [] };
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, statut = 200) => route.fulfill({ status: statut, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) {
      const fn = c.slice(4);
      serveur.appels.push({ fn, corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })(),
        jeton: req.headers()["authorization"] || "", quand: serveur.auth.length });
      if ((fn === "enregistrer_appareil" || fn === "oublier_appareil") && baseAncienne) {
        return d({ code: "PGRST202", message: "Could not find the function public." + fn }, 404);
      }
      if (fn === "enregistrer_appareil" || fn === "oublier_appareil") return d(true);
      if (fn === "mes_livraisons" || fn === "courses_proposees") return d([]);
      return d(null);
    }
    if (c.startsWith("profils")) return d([PROFIL]);
    if (c.startsWith("positions_livreurs")) return d([{ profil_id: LIVREUR, latitude: 6.37, longitude: 2.42 }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => {
    serveur.auth.push(new URL(r.request().url()).pathname);
    return r.fulfill({ status: 200, contentType: "application/json", body: "{}" });
  });
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  return { page, ctx, erreurs, serveur };
}
const declarations = (s) => s.appels.filter((a) => a.fn === "enregistrer_appareil");

titre("1. Connecté : le téléphone se déclare");
{
  const { page, ctx, serveur, erreurs } = await ouvrir();
  await page.waitForTimeout(2500);
  const d = declarations(serveur);
  ok(d.length === 1, "une déclaration au démarrage (" + d.length + ")");
  ok(d[0] && d[0].corps.jeton === JETON && d[0].corps.application === "admin", "avec le jeton du téléphone, pour l'admin");
  ok(d[0] && /^Bearer \S+\.\S+\.\S+$/.test(d[0].jeton), "et la session du compte connecté");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx, serveur } = await ouvrir({ retardJeton: 6000 });
  await page.waitForTimeout(3000);
  ok(declarations(serveur).length === 0, "Firebase pas encore prêt : rien ne part");
  await page.waitForTimeout(7000);
  ok(declarations(serveur).length === 1, "le jeton arrive : la déclaration part ensuite");
  await ctx.close();
}

titre("2. Déconnexion : le téléphone se tait, avant de rendre la session");
{
  const { page, ctx, serveur } = await ouvrir();
  await page.waitForTimeout(2500);
  await page.evaluate(() => { location.hash = "#/compte"; });
  await page.waitForTimeout(1200);
  page.on("dialog", (dl) => dl.accept());
  await page.click("#mc-deconnexion").catch(() => {});
  await page.waitForTimeout(1500);
  const o = serveur.appels.find((a) => a.fn === "oublier_appareil");
  ok(!!o && o.corps.jeton === JETON, "oublier_appareil(jeton) est appelé");
  ok(!!o && /^Bearer /.test(o.jeton), "avec la session encore valable");
  const logout = serveur.auth.findIndex((p) => /logout/.test(p));
  ok(!!o && (logout < 0 || o.quand <= logout), "avant la fin de la session");
  await ctx.close();
}

titre("3. Dans un navigateur : rien ne part");
{
  const { page, ctx, serveur, erreurs } = await ouvrir({ pont: false });
  await page.waitForTimeout(2500);
  ok(declarations(serveur).length === 0, "pas de pont Android : aucune déclaration");
  ok(!erreurs.length, "aucune erreur JavaScript");
  await ctx.close();
}

titre("4. Une base d'avant les notifications push");
{
  const { page, ctx, erreurs } = await ouvrir({ baseAncienne: true });
  await page.waitForTimeout(2500);
  ok(!erreurs.length, "la fonction manque : aucune erreur, l'application continue");
  ok(/Mes courses|course/i.test(await page.evaluate(() => document.body.innerText)), "l'écran des courses s'affiche");
  await ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mLe téléphone de l'équipe se déclare à la connexion, et se tait à la déconnexion ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
