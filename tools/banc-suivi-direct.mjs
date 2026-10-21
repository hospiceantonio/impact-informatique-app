/* =========================================================
   Le suivi des commandes en direct, et « Catalogue mis à jour » (3.59.0)
   =========================================================
     1. ADMIN : la connexion temps réel s'abonne au signal des commandes ;
        quand la base le pousse, l'écran ouvert (ici « Mes courses » du
        livreur) se relit tout seul et montre le nouvel état ;
     2. pas sous les doigts : une feuille ouverte, et l'on attend ;
     3. CLIENT : « Mes commandes » se relit au signal ;
     4. CLIENT : un catalogue qui change sans nouveau produit ne dit plus
        « Catalogue mis à jour » ; un produit qui apparaît : « Nouveau : … ».
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-suivi-direct.mjs");
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
/* Une fausse connexion temps réel : elle note ce qu'on lui envoie, et le
   banc peut lui faire « recevoir » un message de la base. */
const fauxSocket = () => {
  window.__sockets = [];
  class FauxSocket {
    constructor(url) { this.url = url; this.readyState = 0; this.envois = []; window.__sockets.push(this);
      setTimeout(() => { this.readyState = 1; this.onopen && this.onopen(); }, 50); }
    send(t) { this.envois.push(JSON.parse(t)); }
    close() { this.readyState = 3; }
  }
  FauxSocket.OPEN = 1; FauxSocket.CONNECTING = 0;
  window.WebSocket = FauxSocket;
  window.__pousser = (commande) => {
    for (const s of window.__sockets) {
      s.onmessage && s.onmessage({ data: JSON.stringify({ event: "postgres_changes",
        payload: { data: { table: "commandes_signaux", type: "UPDATE", record: { commande_id: commande } } } }) });
    }
  };
  window.__abonne = () => window.__sockets.some((s) => s.envois.some((e) => e.event === "phx_join" &&
    JSON.stringify(e.payload).includes("commandes_signaux")));
};

const LIV = "f1110000-0000-0000-0000-000000000001";
const fiche = { numero: "BZ-000080", retrait: { boutique: "Alpha", adresse: "Ganhi", tel: "0197111222", indicatif: "229" },
  livraison: { nom: "Afi", adresse: "Fidjrossè", note: "", tel: "97666007", indicatif: "229" },
  devise: "FCFA", frais: 1000, deja_paye: 10000, a_encaisser: 0, encaisse: null, momopay: { code: "", nom: "" } };
const course = (etat) => ({ commande_id: "cmd_v", numero: "BZ-000080", boutique_id: "bou_a", nom_boutique: "Alpha",
  client_nom: "Afi", client_tel: "97666007", client_indicatif: "229", client_adresse: "Fidjrossè", note: "",
  etat, articles: [{ nom: "Casque", quantite: 1 }], paye_le: "2026-10-20T08:00:00Z",
  a_encaisser: 0, fiche, recu_le: "2026-10-20T08:05:00Z" });

titre("1-2. Admin : « Mes courses » se relit au signal de la base");
{
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1800 } });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(fauxSocket);
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: a.t, refresh_token: "r", expire_a: Date.now() + 3600000, email: "liv@alpha.bj" }));
  }, { t: jeton(LIV) });
  const etat = { etat: "nouvelle", lectures: 0 };
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    if (c === "rpc/mes_livraisons") { etat.lectures++; return d([course(etat.etat)]); }
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("profils")) return d([{ id: LIV, email: "liv@alpha.bj", nom: "Kodjo", role: "livreur",
      actif: true, peut_modifier_produits: true, boutique_id: "bou_a", tel: "0196000101" }]);
    if (c.startsWith("positions_livreurs")) return d([{ profil_id: LIV, latitude: 6.37, longitude: 2.42, adresse: "Cotonou" }]);
    if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html#/livraisons", { waitUntil: "domcontentloaded" });
  await pause(3000);
  ok(await page.evaluate(() => window.__abonne()), "la connexion temps réel s'abonne au signal des commandes");
  const t0 = await page.evaluate(() => document.querySelector(".lv-course .badge")?.textContent || "");
  ok(/En préparation/.test(t0), "au départ : « En préparation »");
  /* La boutique prépare le colis : la base pousse le signal. */
  etat.etat = "preparee";
  await page.evaluate(() => window.__pousser("cmd_v"));
  await pause(2000);
  const t1 = await page.evaluate(() => document.querySelector(".lv-course .badge")?.textContent || "");
  ok(/À prendre/.test(t1), "le signal arrive : l'écran se relit tout seul — « À prendre » (" + t1 + ")");
  /* Une feuille ouverte : on n'y touche pas, on attend. */
  await page.evaluate(() => UI.ouvrirFeuille("Essai", "<p>en cours</p>"));
  const avant = etat.lectures;
  etat.etat = "en_livraison";
  await page.evaluate(() => window.__pousser("cmd_v"));
  await pause(1500);
  ok(etat.lectures === avant, "une feuille ouverte : l'écran ne se relit pas sous les doigts");
  await page.evaluate(() => UI.fermerFeuille());
  await pause(3000);
  const t2 = await page.evaluate(() => document.querySelector(".lv-course .badge")?.textContent || "");
  ok(etat.lectures > avant && /En cours/.test(t2), "la feuille fermée, il se relit (" + t2 + ")");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

const BOU = [{ id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech", icone: "magasin", couleur: "#0047D9",
  devise: "FCFA", indicatif: "229", whatsapp: "97000001", actif: true, ordre: 1 }];
const CATS = [{ id: "cat_hightech", nom: "High-tech", icone: "informatique", ordre: 1,
  sous_categories: [{ id: "sc_x", nom: "Accessoires", ordre: 1 }] }];
const PROD = (id, nom, stock = 5) => ({ id, boutique_id: "bou_a", nom, code: "00" + id.slice(-2), prix: 5000,
  categorie_id: "cat_hightech", sous_categorie_id: "sc_x", stock, disponible: true, images: [],
  cree_le: "2026-10-01T08:00:00Z", modifie_le: "2026-10-01T08:00:00Z" });

titre("3-4. Client : « Mes commandes » au signal ; le message du catalogue");
{
  const MOI = "f2220000-0000-0000-0000-000000000002";
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1800 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(fauxSocket);
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.setItem("bizzoo-session", JSON.stringify({ access_token: a.t, refresh_token: "r",
      expire_a: Date.now() + 3600000, email: "", tel: "2290196000777" }));
    window.__toasts = [];
    document.addEventListener("DOMContentLoaded", () => {
      const zone = document.querySelector("#toasts");
      if (zone) new MutationObserver(() => {
        for (const t of zone.querySelectorAll(".toast")) if (!t.__vu) { t.__vu = true; window.__toasts.push(t.textContent); }
      }).observe(zone, { childList: true });
    });
  }, { t: jeton(MOI) });
  const etat = { lectures: 0, produits: [PROD("prod_01", "Souris")] };
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("commandes")) { etat.lectures++; return d([]); }
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("clients")) return d([{ id: MOI, nom: "Kiki", tel: "0196000777", indicatif: "229",
      tel_verifie: true, type_compte: "client", revendeur_etat: "aucune", adresse: "Cotonou" }]);
    if (c.startsWith("produits")) return d(etat.produits);
    if (c.startsWith("categories")) return d(CATS);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html#/mes-commandes", { waitUntil: "domcontentloaded" });
  await pause(3500);
  ok(await page.evaluate(() => window.__abonne()), "le client s'abonne au signal de ses commandes");
  const avant = etat.lectures;
  await page.evaluate(() => window.__pousser("cmd_c"));
  await pause(2000);
  ok(etat.lectures > avant, "le signal arrive : « Mes commandes » se relit (" + avant + " → " + etat.lectures + ")");

  /* Une vente fait baisser un stock : l'écran suit, sans message. */
  await page.evaluate(() => { location.hash = "#/"; });
  await pause(1500);
  await page.evaluate(() => { window.__toasts = []; });
  etat.produits = [PROD("prod_01", "Souris", 4)];
  await page.evaluate(() => Catalogue.rafraichir());
  await pause(1500);
  ok(!(await page.evaluate(() => window.__toasts.join(" "))).includes("Catalogue mis à jour"),
    "un stock qui baisse : plus de « Catalogue mis à jour »");
  etat.produits = [PROD("prod_01", "Souris", 4), PROD("prod_02", "Clavier sans fil")];
  await page.evaluate(() => Catalogue.rafraichir());
  await pause(1500);
  ok(/Nouveau : Clavier sans fil/.test(await page.evaluate(() => window.__toasts.join(" "))),
    "un produit apparaît : « Nouveau : Clavier sans fil »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " ÉCHEC(S)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
