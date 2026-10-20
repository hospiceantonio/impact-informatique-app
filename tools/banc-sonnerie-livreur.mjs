/* =========================================================
   La sonnerie du livreur (3.59.0)
   =========================================================
   Une course attend « Commande reçue » : trois notes qui montent, trois
   fois, et le téléphone vibre — puis tout recommence toutes les quatre
   secondes, jusqu'à « Commande reçue ».

     1. une course confiée, pas encore acceptée : sonnerie et vibration ;
     2. elles reprennent toutes les quatre secondes ;
     3. « Commande reçue » : silence, et plus de vibration ;
     4. une demande proposée à tous sonne aussi, et s'arrête quand il la
        prend ;
     5. son coupé dans les réglages : la vibration reste ;
     6. rien n'attend : rien ne sonne ;
     7. un autre livreur prend la demande : la sonnerie s'arrête, « Déjà
        pris par Zinsou » s'affiche, et la carte disparaît.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-sonnerie-livreur.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const jeton = (sub) => {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return b64({ alg: "HS256" }) + "." + b64({ sub }) + ".s";
};
const LIV = "d1110000-0000-0000-0000-000000000001";
const fiche = { numero: "BZ-000070", retrait: { boutique: "Alpha", adresse: "Ganhi", tel: "0197111222", indicatif: "229" },
  livraison: { nom: "Afi", adresse: "Fidjrossè", note: "", tel: "97666007", indicatif: "229" },
  devise: "FCFA", frais: 1000, deja_paye: 10000, a_encaisser: 0, encaisse: null, momopay: { code: "", nom: "" } };
const course = (o = {}) => ({ commande_id: "cmd_s", numero: "BZ-000070", boutique_id: "bou_a", nom_boutique: "Alpha",
  client_nom: "Afi", client_tel: "97666007", client_indicatif: "229", client_adresse: "Fidjrossè", note: "",
  etat: "preparee", articles: [{ nom: "Casque", quantite: 1 }], paye_le: "2026-10-20T08:00:00Z",
  a_encaisser: 0, fiche, recu_le: null, ...o });

async function ouvrir({ courses = [], demandes = [], sonCoupe = false } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1800 } });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: a.t, refresh_token: "r", expire_a: Date.now() + 3600000, email: "liv@alpha.bj" }));
    if (a.sonCoupe) localStorage.setItem("impact-son", "non");
    /* Le son et la vibration, comptés. */
    window.__notes = 0; window.__vibrations = [];
    navigator.vibrate = (p) => { window.__vibrations.push(p); return true; };
    class FauxContexte {
      constructor() { this.state = "running"; this.currentTime = 0; this.destination = {}; }
      resume() { return Promise.resolve(); }
      createOscillator() {
        return { type: "", frequency: { setValueAtTime() {} }, connect() {},
          start() { window.__notes++; }, stop() {} };
      }
      createGain() {
        return { gain: { setValueAtTime() {}, exponentialRampToValueAtTime() {} }, connect() {} };
      }
    }
    window.AudioContext = FauxContexte;
  }, { t: jeton(LIV), sonCoupe });
  const etat = { courses, demandes, notifs: [] };
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const u = new URL(route.request().url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    if (c === "rpc/mes_livraisons") return d(etat.courses);
    if (c === "rpc/courses_proposees") return d(etat.demandes);
    if (c === "rpc/accepter_course") {
      etat.courses = etat.courses.map((x) => ({ ...x, recu_le: "2026-10-20T09:00:00Z" }));
      return d(1);
    }
    if (c === "rpc/prendre_course") {
      etat.courses = etat.demandes.map((x) => course({ commande_id: x.commande_id, recu_le: "2026-10-20T09:00:00Z" }));
      etat.demandes = [];
      return d(1);
    }
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("notifications")) return d(etat.notifs);
    if (c.startsWith("profils")) return d([{ id: LIV, email: "liv@alpha.bj", nom: "Kodjo", role: "livreur",
      actif: true, peut_modifier_produits: true, boutique_id: "bou_a", tel: "0196000101" }]);
    if (c.startsWith("positions_livreurs")) return d([{ profil_id: LIV, latitude: 6.37, longitude: 2.42, adresse: "Cotonou" }]);
    if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html#/livraisons", { waitUntil: "domcontentloaded" });
  await pause(3000);
  return { ctx, page, erreurs, etat };
}
const compte = (page) => page.evaluate(() => ({ notes: window.__notes, vibrations: window.__vibrations.slice() }));

titre("1-3. Une course confiée : ça sonne, ça vibre, ça reprend, jusqu'à « Commande reçue »");
{
  const o = await ouvrir({ courses: [course()] });
  const a = await compte(o.page);
  ok(a.notes >= 9 && a.vibrations.some((v) => Array.isArray(v) && v.length === 5),
    "à l'arrivée : la sonnerie (" + a.notes + " notes) et la vibration");
  await pause(4500);
  const b = await compte(o.page);
  ok(b.notes > a.notes && b.vibrations.length > a.vibrations.length, "quatre secondes plus tard : elle reprend");
  await o.page.click(".lv-recu");
  await pause(1500);
  const c = await compte(o.page);
  ok(c.vibrations.some((v) => v === 0), "« Commande reçue » : la vibration s'arrête");
  await pause(4500);
  const d = await compte(o.page);
  ok(d.notes === c.notes, "et la sonnerie ne revient plus");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("4. Une demande proposée à tous");
{
  const o = await ouvrir({ demandes: [{ commande_id: "cmd_d", numero: "BZ-000071", paye_le: "2026-10-20T08:00:00Z",
    fiche: { ...fiche, groupee: false, retraits: [fiche.retrait] } }] });
  const a = await compte(o.page);
  ok(a.notes >= 9, "elle sonne aussi");
  await o.page.click(".lv-prendre");
  await pause(1500);
  const c = await compte(o.page);
  await pause(4500);
  ok((await compte(o.page)).notes === c.notes, "il la prend : silence");
  await o.ctx.close();
}

titre("5. Son coupé : la vibration reste");
{
  const o = await ouvrir({ courses: [course()], sonCoupe: true });
  const a = await compte(o.page);
  ok(a.notes === 0 && a.vibrations.length >= 1, "pas de son, mais le téléphone vibre");
  await o.ctx.close();
}

titre("6. Rien n'attend");
{
  const o = await ouvrir({ courses: [course({ recu_le: "2026-10-20T09:00:00Z" })] });
  await pause(500);
  const a = await compte(o.page);
  ok(a.notes === 0 && !a.vibrations.some((v) => Array.isArray(v)), "course déjà acceptée : rien ne sonne");
  await o.ctx.close();
}

titre("7. Un autre livreur la prend : « Déjà pris par … »");
{
  const o = await ouvrir({ demandes: [{ commande_id: "cmd_g", numero: "BZ-000072", paye_le: "2026-10-20T08:00:00Z",
    fiche: { ...fiche, groupee: true, retraits: [fiche.retrait, { ...fiche.retrait, boutique: "Bêta" }] } }] });
  ok((await compte(o.page)).notes >= 9 && !!(await o.page.$(".lv-demande")), "la livraison groupée sonne, sa carte est là");
  /* Zinsou la prend : la base envoie la nouvelle, le temps réel fait relire. */
  o.etat.demandes = [];
  o.etat.notifs = [{ id: 901, type: "course_prise", titre: "Déjà pris par Zinsou",
    corps: "Commande BZ-000072 — Zinsou a pris la course. Elle n'est plus disponible.", lien: "#/livraisons",
    commande_id: "cmd_g", boutique_id: null, sonne: false, lue_le: null, cree_le: new Date().toISOString() }];
  await o.page.evaluate(() => Notifs.recharger());
  await pause(2000);
  const c = await compte(o.page);
  ok(c.vibrations.some((v) => v === 0), "la sonnerie et la vibration s'arrêtent");
  const toasts = await o.page.evaluate(() => document.querySelector("#toasts")?.innerText || "");
  ok(/Déjà pris par Zinsou/.test(toasts), "« Déjà pris par Zinsou » s'affiche");
  ok(!(await o.page.$(".lv-demande")) &&
     /Déjà pris par Zinsou/.test(await o.page.evaluate(() => document.getElementById("vue").innerText)),
    "la carte disparaît ; « Déjà pris par Zinsou » reste dans Mes courses");
  await pause(4500);
  ok((await compte(o.page)).notes === c.notes, "et plus rien ne sonne");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " ÉCHEC(S)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
