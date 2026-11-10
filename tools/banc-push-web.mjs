/* =========================================================
   Les notifications dans le navigateur (3.80.0)
   =========================================================
     1. LE CLIENT : « Activer les notifications » demande la permission,
        abonne le navigateur avec la clé de BIZZOO, et le déclare pour
        l'application client ; « Désactiver » l'oublie ;
     2. refusées, iPhone hors écran d'accueil, application Android : la
        carte le dit, ou se tait ;
     3. à l'ouverture, un navigateur abonné se redéclare ; à la
        déconnexion, il s'oublie ;
     4. L'ÉQUIPE et LE VENDEUR : la même carte, pour l'administration.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-push-web.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-push-web.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const plat = (s) => String(s || "").replace(/[  ]/g, " ").replace(/\s+/g, " ").trim();
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const CLIENT = "bbbbbbbb-0000-0000-0000-00000000000b";
const ADMIN = "33333333-3333-3333-3333-333333333333";
const V1 = "c7c7c7c7-0000-0000-0000-000000000001";
const POINT = "https://fcm.googleapis.com/fcm/send/banc-push-web-1";
const CLE_VAPID = "BEl62iUYgUivxIkv69yViEuiBIa-Ib9-SkvMeAtA3LFgDzkrxZJjSgSnfckjBJuBkr3qBUYIHBQFLXYp5Nksh8U";
const corpsDe = (req) => { try { return req.postDataJSON(); } catch (_) { return null; } };
const jeton = (moi) => {
  const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return b64({ alg: "HS256" }) + "." + b64({ sub: moi }) + ".s";
};

/* Le navigateur simulé : service worker, PushManager, Notification. */
function simuler(o) {
  const etat = { courant: null };
  const abonnement = (ep) => ({
    endpoint: ep,
    toJSON: () => ({ endpoint: ep, keys: { p256dh: "B".repeat(87), auth: "a".repeat(22) } }),
    unsubscribe: async () => { etat.courant = null; window.__desabonne = true; return true; },
  });
  if (o.abonne) {
    etat.courant = abonnement(o.point);
    try { localStorage.setItem("bizzoo-push-web", o.point); } catch (_) { /* vide */ }
  }
  const reg = {
    active: {},
    pushManager: {
      getSubscription: async () => etat.courant,
      subscribe: async (x) => {
        window.__cleServeur = x && x.applicationServerKey ? x.applicationServerKey.length : 0;
        etat.courant = abonnement(o.point);
        return etat.courant;
      },
    },
    showNotification: async () => {},
    unregister: async () => true,
  };
  const sw = {
    ready: Promise.resolve(reg), controller: null,
    register: async () => reg, getRegistration: async () => reg, getRegistrations: async () => [],
    addEventListener() {}, removeEventListener() {},
  };
  Object.defineProperty(Navigator.prototype, "serviceWorker", { configurable: true, get: () => sw });
  window.PushManager = function PushManager() {};
  let permission = o.permission;
  window.Notification = class Notification {
    static get permission() { return permission; }
    static async requestPermission() { permission = o.accorder; window.__demandee = true; return permission; }
  };
  if (o.android) window.AndroidPont = { jeton: () => "" };
}

/* ---------- Le client ---------- */
async function ouvrirClient(opts = {}) {
  const o = { permission: "default", accorder: "granted", abonne: false, android: false, point: POINT, ...opts };
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2200 }, serviceWorkers: "block",
    ...(o.iphone ? { userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" } : {}) });
  const page = await ctx.newPage();
  const erreurs = [];
  const appels = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  page.on("dialog", (d) => d.accept());
  await page.addInitScript(({ t }) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
    localStorage.setItem("bizzoo-session", JSON.stringify({
      access_token: t, refresh_token: "r", expire_a: Date.now() + 3600000, email: "awa@exemple.bj" }));
  }, { t: jeton(CLIENT) });
  await page.addInitScript(simuler, o);
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json",
    body: JSON.stringify({ id: CLIENT, email: "awa@exemple.bj", external: { email: true } }) }));
  await page.route("**/realtime/**", (r) => r.abort());
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, s = 200) => route.fulfill({ status: s, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) {
      appels.push({ nom: c.slice(4), corps: corpsDe(req), session: !!req.headers()["authorization"] });
      if (c === "rpc/cle_push_web") return d(CLE_VAPID);
      if (c === "rpc/enregistrer_navigateur" || c === "rpc/oublier_navigateur") return d(true);
      return d(null);
    }
    if (c.startsWith("clients")) return d([{ id: CLIENT, nom: "Awa Dossou", tel: "0196000000",
      adresse: "", tel_verifie: true, type_compte: "client", revendeur_etat: "aucune" }]);
    if (c.startsWith("boutique") && !c.startsWith("boutiques")) {
      return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    }
    return d([]);
  });
  await page.goto(BASE + "/client/index.html#/compte", { waitUntil: "domcontentloaded" });
  await pause(2500);
  return { ctx, page, erreurs, appels };
}
const carte = (page, sel) => page.evaluate((s) => {
  const z = document.querySelector(s);
  return z ? { visible: !z.hidden, texte: z.innerText,
    activer: !!z.querySelector("#pw-activer"), desactiver: !!z.querySelector("#pw-desactiver") } : null;
}, sel).then((x) => x && { ...x, texte: plat(x.texte) });
const toasts = (page) => page.evaluate(() =>
  [...document.querySelectorAll("#toasts .toast")].map((t) => t.textContent).join(" | ")).then(plat);
const sansErreur = (o) => ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));

titre("1. Le client active les notifications");
{
  const o = await ouvrirClient();
  let c = await carte(o.page, "#cp-notifs");
  ok(c && c.visible && /Notifications sur ce navigateur/.test(c.texte) && c.activer,
    "Mon compte : « Notifications sur ce navigateur », avec « Activer les notifications »");
  ok(!o.appels.some((a) => a.nom === "enregistrer_navigateur"),
    "pas encore abonné : rien n'est déclaré à l'ouverture");
  await o.page.click("#pw-activer");
  await pause(800);
  ok(await o.page.evaluate(() => window.__demandee === true), "la permission est demandée au navigateur");
  const cle = o.appels.find((a) => a.nom === "cle_push_web");
  ok(cle, "la clé de BIZZOO est lue");
  ok(await o.page.evaluate(() => window.__cleServeur) === 65, "et sert à l'abonnement (65 octets)");
  const e = o.appels.find((a) => a.nom === "enregistrer_navigateur");
  ok(e && e.corps.point === POINT && e.corps.application === "client" && e.corps.cle.length === 87 &&
     e.corps.secret.length === 22 && e.session,
    "le navigateur est déclaré pour l'application client, avec la session (" + JSON.stringify(e && e.corps.application) + ")");
  ok(/Notifications activées sur ce navigateur/.test(await toasts(o.page)), "« Notifications activées sur ce navigateur. »");
  c = await carte(o.page, "#cp-notifs");
  ok(c && c.desactiver && /même le site fermé/.test(c.texte), "la carte dit « Activées » et propose « Désactiver »");
  ok(await o.page.evaluate(() => localStorage.getItem("bizzoo-push-web")) === POINT, "ce navigateur s'en souvient");

  titre("2. Il les désactive");
  await o.page.click("#pw-desactiver");
  await pause(800);
  const oubli = o.appels.find((a) => a.nom === "oublier_navigateur");
  ok(oubli && oubli.corps.point === POINT, "la base oublie ce navigateur");
  ok(await o.page.evaluate(() => window.__desabonne === true), "le navigateur se désabonne");
  c = await carte(o.page, "#cp-notifs");
  ok(c && c.activer, "la carte propose de nouveau « Activer »");
  sansErreur(o);
  await o.ctx.close();
}

titre("3. Refusées, ou l'abonnement refusé par l'utilisateur");
{
  const o = await ouvrirClient({ permission: "denied" });
  const c = await carte(o.page, "#cp-notifs");
  ok(c && c.visible && /refusées/.test(c.texte) && !c.activer && !c.desactiver,
    "refusées dans le navigateur : la carte explique comment les autoriser");
  await o.ctx.close();
  const p = await ouvrirClient({ accorder: "denied" });
  await p.page.click("#pw-activer");
  await pause(800);
  ok(/Notifications refusées/.test(await toasts(p.page)), "« Bloquer » à la question : un message clair");
  ok(!p.appels.some((a) => a.nom === "enregistrer_navigateur"), "et rien n'est déclaré");
  sansErreur(p);
  await p.ctx.close();
}

titre("4. iPhone, application Android");
{
  const o = await ouvrirClient({ iphone: true });
  const c = await carte(o.page, "#cp-notifs");
  ok(c && c.visible && /écran d'accueil/.test(c.texte) && !c.activer,
    "iPhone dans Safari : « ajoutez BIZZOO à l'écran d'accueil »");
  await o.ctx.close();
  const a = await ouvrirClient({ android: true });
  const ca = await carte(a.page, "#cp-notifs");
  ok(ca && !ca.visible, "dans l'application Android : la carte se tait (Firebase s'en charge)");
  await a.ctx.close();
}

titre("5. À l'ouverture, abonné : redéclaré ; à la déconnexion : oublié");
{
  const o = await ouvrirClient({ permission: "granted", abonne: true });
  const e = o.appels.find((a) => a.nom === "enregistrer_navigateur");
  ok(e && e.corps.point === POINT && e.corps.application === "client",
    "à l'ouverture, le navigateur abonné sonne pour CE compte");
  const c = await carte(o.page, "#cp-notifs");
  ok(c && c.desactiver, "la carte le dit « Activées »");
  await o.page.click("#cp-sortir");
  await pause(1500);
  const oubli = o.appels.find((a) => a.nom === "oublier_navigateur");
  ok(oubli && oubli.corps.point === POINT, "se déconnecter : la base oublie ce navigateur");
  ok(await o.page.evaluate(() => !localStorage.getItem("bizzoo-push-web")), "et ce navigateur aussi");
  sansErreur(o);
  await o.ctx.close();
}

/* ---------- L'administration ---------- */
async function ouvrirAdmin({ role = "administrateur", moi = ADMIN, hash = "#/compte" } = {}) {
  const o = { permission: "default", accorder: "granted", abonne: false, android: false, point: POINT };
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2200 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  const appels = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  page.on("dialog", (d) => d.accept());
  await page.addInitScript((m) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({ access_token: m, refresh_token: "r",
      expire_a: Date.now() + 3600000, email: "x@bizzoo.bj" }));
  }, jeton(moi));
  await page.addInitScript(simuler, o);
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const c = url.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) {
      appels.push({ nom: c.slice(4), corps: corpsDe(req), session: !!req.headers()["authorization"] });
      if (c === "rpc/cle_push_web") return d(CLE_VAPID);
      if (c === "rpc/enregistrer_navigateur") return d(true);
      if (c === "rpc/espace_vendeur") return d({ vendeur: { id: V1, nom: "Afi", tel: "0197700001" },
        solde: { ventes: 0, gagne: 0, a_venir: 0, reverse: 0, en_attente: 0, disponible: 0, devise: "FCFA", reception: null },
        produits: [], lignes: [], versements: [] });
      return d(null);
    }
    if (c.startsWith("profils")) {
      return d([{ id: moi, email: "x@bizzoo.bj", role, actif: true, nom: "Moi", peut_modifier_produits: true,
        boutique_id: role === "administrateur" ? "bou_marche" : null }]);
    }
    if (c.startsWith("boutique") && !c.startsWith("boutiques")) {
      return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    }
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await pause(1500);
  await page.evaluate((h) => { location.hash = h; }, hash);
  await pause(1500);
  return { ctx, page, erreurs, appels };
}

titre("6. L'équipe : Mon compte");
{
  const o = await ouvrirAdmin();
  const c = await carte(o.page, "#mc-notifs");
  ok(c && c.visible && c.activer, "Mon compte : la carte « Notifications sur ce navigateur »");
  await o.page.click("#pw-activer");
  await pause(800);
  const e = o.appels.find((a) => a.nom === "enregistrer_navigateur");
  ok(e && e.corps.point === POINT && e.corps.application === "admin" && e.session,
    "le navigateur est déclaré pour l'administration, avec la session");
  sansErreur(o);
  await o.ctx.close();
}

titre("7. Le vendeur : son espace");
{
  const o = await ouvrirAdmin({ role: "vendeur", moi: V1, hash: "#/ventes" });
  const c = await carte(o.page, "#vd-notifs");
  ok(c && c.visible && c.activer, "son espace : la carte, pour être prévenu de chaque commande");
  await o.page.click("#vd-notifs #pw-activer");
  await pause(800);
  const e = o.appels.find((a) => a.nom === "enregistrer_navigateur");
  ok(e && e.corps.application === "admin", "déclaré pour l'administration, où arrivent ses commandes");
  sansErreur(o);
  await o.ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mLes notifications s'activent dans le navigateur, client comme administration ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
