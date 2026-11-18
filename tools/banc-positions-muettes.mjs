/* =========================================================
   Banc : les livreurs dont la position n'arrive plus (4.7.0)

   Un livreur « disponible » envoie sa position toutes les 3 minutes,
   application fermée. Sans position depuis une heure, il passe pour
   « loin » et ne reçoit les courses qu'en dernier. L'écran Livreurs dit
   désormais qui appeler.

   Ce qu'on prouve :
     1. le superadministrateur : « Positions reçues : 1 sur 3 », les deux
        livreurs muets, le plus ancien d'abord, avec leur numéro à
        appeler ; pas celui qui s'est dit « pas disponible », ni celui
        qui est désactivé, ni celui qui n'a jamais validé sa position ;
     2. l'administrateur de BIZZOO la voit aussi ;
     3. l'administrateur d'une boutique : ses livreurs seulement ;
     4. tout arrive : la carte le dit, sans liste.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-positions-muettes.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-positions-muettes.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const plat = (s) => String(s || "").replace(/[  ]/g, " ").replace(/\s+/g, " ").trim();
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const jeton = (sub) => {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return b64({ alg: "HS256" }) + "." + b64({ sub }) + ".s";
};
const SUP = "11111111-1111-1111-1111-111111111111";
const ADMBZ = "c7c70000-0000-0000-0000-000000000002";
const CHEF = "c7c70000-0000-0000-0000-000000000003";
const L = (n) => "c7c70000-0000-0000-0000-0000000000a" + n;
const ilYA = (min) => new Date(Date.now() - min * 60000).toISOString();
const PROFILS = {
  [SUP]: { id: SUP, email: "sup@bizzoo.bj", nom: "Sup", role: "superadministrateur", actif: true, boutique_id: null, peut_modifier_produits: true },
  [ADMBZ]: { id: ADMBZ, email: "admin@bizzoo.bj", nom: "Admin BZ", role: "administrateur", actif: true, boutique_id: null, peut_modifier_produits: true },
  [CHEF]: { id: CHEF, email: "chef@alpha.bj", nom: "Chef", role: "administrateur", actif: true, boutique_id: "bou_a", peut_modifier_produits: true },
};
const liv = (n, nom, tel, plus) => ({ id: L(n), email: "", nom, tel, role: "livreur", actif: true, boutique_id: null,
  disponible: true, vehicule: "moto", ...plus });
const LIVREURS = [
  liv(1, "Awa Fraîche", "0197000001"),                         // position il y a 5 min
  liv(2, "Bio Muet", "0197000002"),                            // il y a 3 h
  liv(3, "Codjo Très Muet", "0197000003"),                     // il y a 5 jours
  liv(4, "Dossou Pas Dispo", "0197000004", { disponible: false }),
  liv(5, "Essè Désactivé", "0197000005", { actif: false }),
  liv(6, "Fifa Jamais Validée", "0197000006"),                 // aucune position
  liv(7, "Gildas De La Boutique", "0197000007", { boutique_id: "bou_a" }),   // il y a 2 jours
];
const POSITIONS = (toutFrais) => [
  { profil_id: L(1), latitude: 6.37, longitude: 2.42, adresse: "Cotonou", enregistre_le: ilYA(5) },
  { profil_id: L(2), latitude: 6.37, longitude: 2.42, adresse: "Cotonou", enregistre_le: ilYA(toutFrais ? 10 : 180) },
  { profil_id: L(3), latitude: 6.37, longitude: 2.42, adresse: "Cotonou", enregistre_le: ilYA(toutFrais ? 20 : 5 * 1440) },
  { profil_id: L(4), latitude: 6.37, longitude: 2.42, adresse: "Cotonou", enregistre_le: ilYA(4000) },
  { profil_id: L(5), latitude: 6.37, longitude: 2.42, adresse: "Cotonou", enregistre_le: ilYA(4000) },
  { profil_id: L(7), latitude: 6.37, longitude: 2.42, adresse: "Cotonou", enregistre_le: ilYA(toutFrais ? 30 : 2 * 1440) },
];

async function ouvrir(moi, toutFrais) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2600 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: a.t, refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
  }, { t: jeton(moi), email: PROFILS[moi].email });
  /* Ce que la base laisse voir : à la boutique, ses livreurs et ceux de BIZZOO (par livreurs_boutique). */
  const visibles = moi === CHEF ? LIVREURS.filter((l) => l.boutique_id === "bou_a") : LIVREURS;
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const c = url.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    if (c === "rpc/livreurs_boutique") {
      return d(LIVREURS.filter((l) => l.boutique_id === null || l.boutique_id === "bou_a").map((l) => ({
        id: l.id, email: l.email, nom: l.nom, tel: l.tel, actif: l.actif, bizzoo: l.boutique_id === null })));
    }
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("positions_livreurs")) {
      return d(moi === CHEF ? POSITIONS(toutFrais).filter((p) => p.profil_id === L(7)) : POSITIONS(toutFrais));
    }
    if (c.startsWith("profils")) {
      if (url.searchParams.get("id")) return d([PROFILS[moi]]);
      return d([PROFILS[moi], ...visibles]);
    }
    if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha", categorie_id: null, icone: "magasin", couleur: "#0B7C8C",
      devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await pause(2200);
  await page.evaluate(() => { location.hash = "#/livreurs"; });
  await pause(1600);
  const carte = plat(await page.evaluate(() => (document.querySelector("#lp-muets") || {}).innerText || ""));
  const noms = await page.evaluate(() => [...document.querySelectorAll("#lp-muets .lp-muet strong")].map((x) => x.textContent));
  return { ctx, page, erreurs, carte, noms };
}
const sansErreur = (o) => ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));

titre("1. Le superadministrateur : qui appeler");
{
  const o = await ouvrir(SUP);
  ok(/Positions reçues : 1 sur 4/.test(o.carte), "« Positions reçues : 1 sur 4 » (les livreurs disponibles, actifs, validés)");
  ok(o.noms.join(" | ") === "Codjo Très Muet | Gildas De La Boutique | Bio Muet", "les muets, le plus ancien d'abord (" + o.noms.join(" | ") + ")");
  ok(/3 livreurs à appeler/.test(o.carte) && /Dernière position : il y a 5 jours/.test(o.carte) && /il y a 3 h/.test(o.carte),
    "« 3 livreurs à appeler », avec l'âge de la dernière position");
  ok(await o.page.evaluate((id) => (document.querySelector('[data-muet="' + id + '"] a') || {}).getAttribute?.("href"), L(2)) === "tel:0197000002",
    "son numéro s'appelle d'un toucher");
  ok(!/Pas Dispo|Désactivé|Jamais Validée|Awa/.test(o.noms.join(" ")),
    "pas celui qui n'est « pas disponible », ni le désactivé, ni celui sans position, ni celui dont la position arrive");
  ok(/Toujours autoriser/.test(o.carte) && /en dernier/.test(o.carte), "la carte dit pourquoi, et quoi lui faire régler");
  sansErreur(o);
  await o.ctx.close();
}

titre("2. L'administrateur de BIZZOO la voit aussi");
{
  const o = await ouvrir(ADMBZ);
  ok(/Positions reçues : 1 sur 4/.test(o.carte) && o.noms.length === 3, "la même carte, les mêmes trois livreurs");
  sansErreur(o);
  await o.ctx.close();
}

titre("3. L'administrateur d'une boutique : ses livreurs seulement");
{
  const o = await ouvrir(CHEF);
  ok(/Positions reçues : 0 sur 1/.test(o.carte) && o.noms.join("|") === "Gildas De La Boutique",
    "« 0 sur 1 » : le livreur de sa boutique, pas ceux de BIZZOO (" + o.noms.join("|") + ")");
  sansErreur(o);
  await o.ctx.close();
}

titre("4. Tout arrive");
{
  const o = await ouvrir(SUP, true);
  ok(/Positions reçues : 4 sur 4/.test(o.carte) && !o.noms.length && !/à appeler/.test(o.carte), "« 4 sur 4 », et personne à appeler");
  sansErreur(o);
  await o.ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mL'écran Livreurs dit dont la position n'arrive plus, et qui appeler ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
