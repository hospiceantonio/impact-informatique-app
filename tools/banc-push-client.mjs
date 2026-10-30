/* =========================================================
   Banc — le téléphone du CLIENT déclaré pour le push (3.70.0)

   La base route la notification d'un acheteur vers l'application client
   (supabase/tests/99zzz…-sms-clients.sql, tools/eprouver-push.sh). Ce
   banc regarde l'application client dans sa coquille Android (pont
   simulé) :

     1. connecté, elle déclare le jeton du téléphone à la base, au nom
        de l'application « client » — même quand Firebase ne le donne
        qu'après quelques secondes ;
     2. à la déconnexion, elle le retire AVANT de rendre la session ;
     3. sans compte, ou dans un navigateur (pas de pont), rien ne part.

     PLAYWRIGHT=… CHROMIUM=… BANC_URL=http://127.0.0.1:5191 node tools/banc-push-client.mjs
   ========================================================= */
const { chromium } = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default;
const BASE = process.env.BANC_URL || "http://127.0.0.1:5191";
const EXE = process.env.CHROMIUM || undefined;
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE, args: ["--no-sandbox"] } : { args: ["--no-sandbox"] });

const MOI = "e5e5e5e5-0000-0000-0000-0000000000aa";
const JETON = "jeton-firebase-du-client-0123456789";
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const jwt = (o) => b64({ alg: "HS256" }) + "." + b64(o) + ".s";

async function ouvrir({ pont = true, connecte = true, retard = 0, permis = true, oubliEnPanne = false } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1600 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    if (a.s && !localStorage.getItem("banc-sans-session")) localStorage.setItem("bizzoo-session", JSON.stringify(a.s));
    if (a.pont) {
      const debut = Date.now();
      window.AndroidPont = { jetonPush: () => (Date.now() - debut >= a.retard ? a.jeton : ""),
        notificationsPermises: () => a.permis };
    }
  }, { permis, s: connecte ? { access_token: jwt({ sub: MOI, phone: "2290196000222", email: "" }), refresh_token: "r",
      expire_a: Date.now() + 3600000, email: "", tel: "2290196000222" } : null, pont, retard, jeton: JETON });
  const serveur = { appels: [], oubliEnPanne };
  await page.route("**/auth/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/auth\/v1\//, "");
    serveur.appels.push({ fn: "auth/" + c.split("?")[0] });
    if (c === "settings") return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ external: { phone: true } }) });
    return r.fulfill({ status: 200, contentType: "application/json", body: "{}" });
  });
  await page.route("**/rest/v1/**", (r) => {
    const req = r.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) {
      serveur.appels.push({ fn: c.slice(4), corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })(),
        jeton: req.headers()["authorization"] || "" });
      if ((c === "rpc/oublier_appareil" || c === "rpc/oublier_jeton_push") && serveur.oubliEnPanne) {
        return r.fulfill({ status: 503, contentType: "application/json", body: "{}" });
      }
      if (c === "rpc/enregistrer_appareil" || c === "rpc/oublier_appareil" || c === "rpc/oublier_jeton_push") return d(true);
      return d(null);
    }
    if (c.startsWith("clients")) {
      return d([{ id: MOI, nom: "Afi", tel: "0196000222", indicatif: "229", tel_verifie: true,
        type_compte: "client", revendeur_etat: "aucune", adresse: "Cotonou" }]);
    }
    return d([]);
  });
  await page.goto(BASE + "/client/index.html#/compte");
  await pause(2500 + retard);
  return { ctx, page, erreurs, serveur };
}

titre("1. Connecté, dans l'application Android : le téléphone est déclaré");
{
  const o = await ouvrir({ retard: 3000 });
  await pause(5000);
  const decl = o.serveur.appels.filter((a) => a.fn === "enregistrer_appareil");
  ok(decl.length >= 1, "le téléphone est déclaré à la base, même si Firebase tarde (" + decl.length + ")");
  ok(decl[0] && decl[0].corps.jeton === JETON && decl[0].corps.application === "client",
    "avec SON jeton, au nom de l'application client (« " + (decl[0] && decl[0].corps.application) + " »)");
  ok(decl[0] && /Bearer .+\..+\./.test(decl[0].jeton), "avec la session du compte (la base sait à qui)");

  titre("2. À la déconnexion : retiré AVANT de rendre la session");
  o.serveur.appels.length = 0;
  await o.page.evaluate(() => Compte.deconnecter());
  await pause(800);
  const ordre = o.serveur.appels.map((a) => a.fn);
  const iOubli = ordre.indexOf("oublier_appareil");
  const iSortie = ordre.findIndex((f) => /^auth\/logout/.test(f));
  ok(iOubli >= 0, "le téléphone est retiré à la déconnexion");
  ok(iOubli >= 0 && iSortie >= 0 && iOubli < iSortie, "avant que la session soit rendue (" + ordre.join(" → ") + ")");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("2 bis. Notifications refusées sur ce téléphone : il n'est pas déclaré");
{
  const o = await ouvrir({ permis: false });
  await pause(1500);
  ok(!o.serveur.appels.some((a) => a.fn === "enregistrer_appareil"),
    "le téléphone n'est pas déclaré : la base enverra le SMS à la place");
  ok(o.serveur.appels.some((a) => a.fn === "oublier_appareil" && a.corps.jeton === JETON),
    "et il est retiré s'il l'était (les notifications ont été coupées depuis)");
  await o.ctx.close();
}

titre("2 ter. Déconnecté sans réseau : retiré à la prochaine ouverture");
{
  const o = await ouvrir({ oubliEnPanne: true });
  await pause(1500);
  await o.page.evaluate(() => Compte.deconnecter());
  await pause(600);
  const enSuspens = await o.page.evaluate(() => localStorage.getItem("bizzoo-push-a-oublier"));
  ok(enSuspens === JETON, "le retrait a échoué : il est gardé pour plus tard");
  o.serveur.appels.length = 0;
  o.serveur.oubliEnPanne = false;
  await o.page.evaluate(() => localStorage.setItem("banc-sans-session", "1"));
  await o.page.reload();
  await pause(2500);
  const rattrape = o.serveur.appels.find((a) => a.fn === "oublier_jeton_push");
  ok(rattrape && rattrape.corps.jeton === JETON, "à la réouverture, sans compte : le téléphone est retiré avec son seul jeton");
  ok(await o.page.evaluate(() => localStorage.getItem("bizzoo-push-a-oublier")) === null, "puis l'oubli en suspens est effacé");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("3. Sans compte, ou dans un navigateur : rien ne part");
{
  const o = await ouvrir({ connecte: false });
  await pause(1500);
  ok(!o.serveur.appels.some((a) => a.fn === "enregistrer_appareil"), "sans compte : rien n'est déclaré");
  await o.ctx.close();
}
{
  const o = await ouvrir({ pont: false });
  await pause(1500);
  ok(!o.serveur.appels.some((a) => a.fn === "enregistrer_appareil"), "dans un navigateur (pas de pont) : rien n'est déclaré");
  ok(!o.erreurs.length, "et rien ne casse");
  await o.ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " échec(s)" : "\nTout passe.");
process.exit(echecs ? 1 : 0);
