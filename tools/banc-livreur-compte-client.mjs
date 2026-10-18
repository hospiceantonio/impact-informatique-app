/* =========================================================
   Un livreur dans l'application client (3.59.0)
   =========================================================
   Le constat du CEO : un livreur qui ouvrait l'application client avec
   son numéro se voyait proposer « Devenir revendeur », « Mes commandes »
   et « Retrouver mes commandes d'avant », comme un acheteur. La base le
   refuse désormais (supabase/tests/99zzzz-livreur-pas-client.sql) ; les
   écrans :

     1. le compte du livreur : ni revendeur, ni « Mes commandes », ni
        « Retrouver » ; « Mes courses » à la place, et l'espace vendeur ;
     2. « Mes courses » : à livrer, livrées, ce qu'il y a à encaisser ;
     3. un compte client « double » (ouvert avec le numéro d'un livreur) :
        on lui dit d'entrer avec son compte livreur ;
     4. un client ordinaire : rien ne change ;
     5. s'inscrire avec le numéro d'un livreur : un message clair.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-livreur-compte-client.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const jwt = (c) => b64({ alg: "HS256" }) + "." + b64(c) + ".s";
const MOI = "55550000-0000-0000-0000-000000000005";

const COURSES = [
  { commande_id: "c1", numero: "BZ-101", boutique_id: "b1", nom_boutique: "Alpha", client_nom: "Afi",
    client_tel: "97000001", client_indicatif: "229", client_adresse: "Fidjrossè", note: "",
    etat: "en_livraison", articles: [{ nom: "Câble", quantite: 2 }], paye_le: "2026-10-17T08:00:00Z", a_encaisser: 3500 },
  { commande_id: "c2", numero: "BZ-099", boutique_id: "b1", nom_boutique: "Alpha", client_nom: "Koffi",
    client_tel: "97000002", client_indicatif: "229", client_adresse: "Akpakpa", note: "",
    etat: "remise", articles: [{ nom: "Souris", quantite: 1 }], paye_le: "2026-10-16T08:00:00Z", a_encaisser: 0 },
];

async function ouvrir({ sorte, hash = "#/compte", connecte = true, inscription = false }) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2200 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(({ s }) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    if (s) localStorage.setItem("bizzoo-session", JSON.stringify(s));
    window.__toasts = [];
    document.addEventListener("DOMContentLoaded", () => {
      const zone = document.querySelector("#toasts");
      if (zone) new MutationObserver(() => {
        for (const t of zone.querySelectorAll(".toast")) if (!t.__vu) { t.__vu = true; window.__toasts.push(t.textContent); }
      }).observe(zone, { childList: true });
    });
  }, { s: connecte ? { access_token: jwt({ sub: MOI, phone: "2290196000111", email: "" }), refresh_token: "r",
    expire_a: Date.now() + 3600000, email: "", tel: "2290196000111" } : null });
  await page.route("**/auth/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/auth\/v1\//, "");
    if (c === "settings") return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ external: { phone: true } }) });
    if (c === "signup" && inscription) {
      return r.fulfill({ status: 500, contentType: "application/json",
        body: JSON.stringify({ code: 500, error_code: "unexpected_failure", msg: "Database error saving new user" }) });
    }
    return r.fulfill({ status: 200, contentType: "application/json", body: "{}" });
  });
  await page.route("**/rest/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/mon_compte_livreur") return d({ livreur: sorte === "livreur", double: sorte === "double" });
    if (c === "rpc/mes_livraisons") return d(sorte === "livreur" ? COURSES : []);
    if (c.startsWith("profils")) return d(sorte === "livreur" ? [{ id: MOI }] : []);
    if (c.startsWith("clients")) {
      return d(sorte === "livreur" ? [] : [{ id: MOI, nom: "Kossi", tel: "0196000111", indicatif: "229",
        tel_verifie: true, type_compte: "client", revendeur_etat: "aucune", adresse: "Cotonou" }]);
    }
    return d([]);
  });
  await page.goto(BASE + "/client/index.html" + hash);
  await pause(3000);
  return { ctx, page, erreurs };
}
const texte = (page) => page.evaluate(() => document.getElementById("vue").innerText.replace(/\s+/g, " "));
const ilYa = (page, s) => page.evaluate((s) => !!document.querySelector(s), s);
const sansErreur = (o) => ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));

titre("1. Le compte du livreur : pas un acheteur");
{
  const o = await ouvrir({ sorte: "livreur" });
  const t = await texte(o.page);
  ok(!/Vous achetez pour revendre|Devenir revendeur|Compte revendeur/.test(t) && !(await ilYa(o.page, "#cp-rv-envoyer")),
    "aucune proposition de devenir revendeur");
  ok(!(await ilYa(o.page, 'a[href="#/mes-commandes"]')), "pas de « Mes commandes »");
  ok(!(await ilYa(o.page, "#cp-reprendre")) && !/Retrouver mes commandes/.test(t), "pas de « Retrouver mes commandes d'avant »");
  ok(!(await ilYa(o.page, "#cp-verifier")), "pas de « Vérifier par SMS » d'acheteur");
  ok(await ilYa(o.page, 'a[href="#/mes-courses"]') && /Mes courses/.test(t), "« Mes courses » à la place");
  ok(/Espace vendeur/.test(t), "l'espace vendeur reste proposé");
  sansErreur(o);

  titre("2. Mes courses");
  await o.page.click("#cp-mes-courses");
  await pause(1500);
  const c = await texte(o.page);
  ok(/À livrer \(1\)/.test(c) && /BZ-101/.test(c) && /En livraison/.test(c), "à livrer : la commande BZ-101, en livraison");
  ok(/Livrées \(1\)/.test(c) && /BZ-099/.test(c), "livrées : BZ-099");
  ok(/Afi/.test(c) && /Fidjrossè/.test(c) && /2 × Câble/.test(c), "le client, l'adresse, les articles");
  ok(/À encaisser : 3\s?500 FCFA/.test(c), "ce qu'il y a à encaisser");
  sansErreur(o);
  await o.ctx.close();
}

titre("3. Le compte client ouvert avec le numéro d'un livreur");
{
  const o = await ouvrir({ sorte: "double" });
  const t = await texte(o.page);
  ok(await ilYa(o.page, "#cp-double-livreur") && /celui d'un livreur/.test(t),
    "on lui dit que ce numéro est celui d'un livreur");
  ok(!/Vous achetez pour revendre|Compte revendeur/.test(t) && !(await ilYa(o.page, 'a[href="#/mes-commandes"]')) &&
     !(await ilYa(o.page, "#cp-reprendre")), "ni revendeur, ni commandes, ni « Retrouver »");
  await o.page.click("#cp-double-sortir");
  await pause(1500);
  ok(await o.page.evaluate(() => !Compte.connecte() && location.hash === "#/connexion"),
    "« Me déconnecter » : il revient à la connexion, pour entrer avec son compte livreur");
  sansErreur(o);
  await o.ctx.close();
}
{
  const o = await ouvrir({ sorte: "double", hash: "#/mes-courses" });
  ok(await ilYa(o.page, "#cp-courses-double"), "« Mes courses » d'un double : ses courses sont dans son compte livreur");
  await o.ctx.close();
}

titre("4. Un client ordinaire : rien ne change");
{
  const o = await ouvrir({ sorte: "client" });
  const t = await texte(o.page);
  ok(await ilYa(o.page, 'a[href="#/mes-commandes"]') && !(await ilYa(o.page, 'a[href="#/mes-courses"]')),
    "« Mes commandes », pas de « Mes courses »");
  ok(/Vous achetez pour revendre/.test(t), "la demande de revendeur lui est proposée");
  ok(await ilYa(o.page, "#cp-reprendre"), "« Retrouver mes commandes d'avant » reste");
  sansErreur(o);
  await o.ctx.close();
}
{
  const o = await ouvrir({ sorte: "client", hash: "#/mes-courses" });
  ok(await o.page.evaluate(() => location.hash) === "#/mes-commandes", "« Mes courses » renvoie un client à ses commandes");
  await o.ctx.close();
}

titre("5. S'inscrire avec le numéro d'un livreur");
{
  const o = await ouvrir({ sorte: "client", connecte: false, hash: "#/inscription", inscription: true });
  await o.page.fill("#cp-nom", "Kossi");
  await o.page.fill("#cp-tel", "0196000111");
  await o.page.fill("#cp-mdp-nouveau", "secret-essai");
  await o.page.fill("#cp-mdp-encore", "secret-essai");
  await o.page.click("#cp-creer-tel");
  await pause(1000);
  const t = await o.page.evaluate(() => (window.__toasts || []).join(" | "));
  ok(/celui d'un livreur BIZZOO/.test(t) && !/Database error/i.test(t),
    "le refus de la base se lit en français : entrer avec son compte livreur");
  ok(!(await ilYa(o.page, "#cp-code")), "pas d'écran de code");
  sansErreur(o);
  await o.ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec." : "\nTous les constats sont bons.");
process.exit(echecs ? 1 : 0);
