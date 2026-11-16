/* =========================================================
   Banc : l'administrateur de BIZZOO crée un vendeur SUR PLACE (4.5.0)

   Il est chez le vendeur. Il crée son compte, et la fiche de son lieu
   s'ouvre aussitôt : adresse, « Je suis chez lui : ma position » (la
   position de SON téléphone), horaires. Le vendeur naît inactif ; le
   superadministrateur vérifie le lieu, puis le valide.

   Ce qu'on prouve :
     1. l'administrateur de BIZZOO crée le vendeur : le compte part
        inactif, puis la fiche du lieu s'ouvre d'elle-même ; la position
        de son téléphone devient celle du vendeur, et s'enregistre ;
     2. il retrouve, dans Comptes, ses vendeurs en attente, avec leur
        lieu — et pas ceux d'un autre administrateur ;
     3. le superadministrateur les voit en tête de l'écran Vendeurs,
        « À valider », avec leur lieu ; « Valider » les active ; la
        notification ouvre leur lieu ;
     4. dans Comptes aussi, le superadministrateur les trouve « À valider ».

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-vendeur-sur-place.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-vendeur-sur-place.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const plat = (s) => String(s || "").replace(/[  ]/g, " ").replace(/\s+/g, " ");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const jeton = (sub) => {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return b64({ alg: "HS256" }) + "." + b64({ sub }) + ".s";
};
const ADMBZ = "c4c40000-0000-0000-0000-000000000001";
const ADMBZ2 = "c4c40000-0000-0000-0000-000000000002";
const SUP = "11111111-1111-1111-1111-111111111111";
const V1 = "c4c40000-0000-0000-0000-0000000000a1";   // à valider, créé par ADMBZ
const V2 = "c4c40000-0000-0000-0000-0000000000a2";   // à valider, créé par ADMBZ2
const V3 = "c4c40000-0000-0000-0000-0000000000a3";   // en service
const NEUF = "c4c40000-0000-0000-0000-0000000000a9"; // celui qu'on crée
const ICI = { latitude: 6.3702, longitude: 2.4289 };

const PROFILS = {
  [ADMBZ]: { id: ADMBZ, email: "admin@bizzoo.bj", nom: "Admin BZ", role: "administrateur", actif: true, boutique_id: null, peut_modifier_produits: true },
  [ADMBZ2]: { id: ADMBZ2, email: "admin2@bizzoo.bj", nom: "Admin Deux", role: "administrateur", actif: true, boutique_id: null, peut_modifier_produits: true },
  [SUP]: { id: SUP, email: "sup@bizzoo.bj", nom: "Sup", role: "superadministrateur", actif: true, boutique_id: null, peut_modifier_produits: true },
};
const VENDEURS = [
  { id: V1, email: "", nom: "Pagnes Afi", tel: "0197800001", role: "vendeur", actif: false, a_valider: true,
    boutique_id: null, cree_par: ADMBZ, cree_par_nom: "Admin BZ", cree_le: "2026-11-15T09:00:00Z" },
  { id: V2, email: "", nom: "Chez Koffi", tel: "0197800002", role: "vendeur", actif: false, a_valider: true,
    boutique_id: null, cree_par: ADMBZ2, cree_par_nom: "Admin Deux", cree_le: "2026-11-15T10:00:00Z" },
  { id: V3, email: "", nom: "Tissus Ayi", tel: "0197800003", role: "vendeur", actif: true, a_valider: false,
    boutique_id: null, cree_par: SUP, cree_par_nom: "Sup", cree_le: "2026-10-01T09:00:00Z" },
];
const BOU = [{ id: "bou_m", nom: "Marché", categorie_id: null, icone: "magasin", couleur: "#0B7C8C",
  devise: "FCFA", indicatif: "229", actif: true, ordre: 1, vendeurs: "multiples", part_vendeur_max: 80 }];
const ventes = (v) => ({ id: v.id, nom: v.nom, tel: v.tel, actif: v.actif, produits: 0, ventes: 0, part: 0,
  commission: 0, a_venir: 0, reverse: 0, en_attente: 0, disponible: 0 });

async function ouvrir(moi, hash) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2400 }, serviceWorkers: "block",
    geolocation: ICI, permissions: ["geolocation"] });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  page.on("dialog", (d) => d.accept());
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: a.t, refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
  }, { t: jeton(moi), email: PROFILS[moi].email });
  const ecrits = [];
  /* Ce que la base laisse voir à chacun : le superadministrateur, tout ;
     l'administrateur de BIZZOO, les vendeurs (la règle « est_equipe »). */
  const comptes = [PROFILS[moi], ...VENDEURS];
  await page.route("**/auth/v1/**", (r) => {
    const u = new URL(r.request().url()).pathname;
    if (u.endsWith("/signup")) {
      ecrits.push({ quoi: "signup", corps: r.request().postDataJSON() });
      return r.fulfill({ status: 200, contentType: "application/json",
        body: JSON.stringify({ user: { id: NEUF, identities: [{ id: "i" }] } }) });
    }
    return r.fulfill({ status: 200, contentType: "application/json", body: "{}" });
  });
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const c = url.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    let corps = null;
    try { corps = req.postDataJSON(); } catch (_) { corps = null; }
    if (req.method() !== "GET") ecrits.push({ quoi: req.method() + " " + c + url.search, corps });
    if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    if (c === "rpc/ventes_vendeurs") return d(VENDEURS.map(ventes));
    if (c === "rpc/lieux_vendeurs") {
      return d([{ vendeur_id: V1, nom: "Pagnes Afi", tel: "0197800001", adresse: "Dantokpa, allée 4",
        latitude: 6.3702, longitude: 2.4289, horaires: true }]);
    }
    if (c === "rpc/lieu_vendeur") {
      return d(corps && corps.cible === V1
        ? { nom: "Pagnes Afi", tel: "0197800001", indicatif: "229", adresse: "Dantokpa, allée 4",
            latitude: 6.3702, longitude: 2.4289, ouvertures: null, connu: true }
        : { nom: "", tel: "", indicatif: "229", adresse: "", latitude: null, longitude: null, ouvertures: null, connu: false });
    }
    if (c === "rpc/enregistrer_lieu_vendeur") {
      const l = (corps && corps.lieu) || {};
      return d({ ...l, connu: true });
    }
    if (c === "rpc/parts_vendeurs_historique_liste" || c === "rpc/vendeurs_liste") return d([]);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("profils")) {
      if (req.method() === "PATCH") {
        const id = (url.searchParams.get("id") || "").replace(/^eq\./, "");
        const v = comptes.find((x) => x.id === id) || { id };
        return d([{ ...v, ...corps, a_valider: corps && corps.actif ? false : v.a_valider }]);
      }
      if (req.method() !== "GET") return d([{ ...(corps || {}), a_valider: corps && corps.actif === false }]);
      if (url.searchParams.get("id")) {
        const id = url.searchParams.get("id").replace(/^eq\./, "");
        return d(comptes.filter((x) => x.id === id));
      }
      return d(comptes);
    }
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await pause(2200);
  if (hash) { await page.evaluate((h) => { location.hash = h; }, hash); await pause(1500); }
  return { ctx, page, erreurs, ecrits };
}
const texte = (page, sel) => page.evaluate((s) => (document.querySelector(s) || {}).innerText || "", sel).then(plat);
const sansErreur = (o) => ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));

titre("1. L'administrateur de BIZZOO crée le vendeur, puis pose son lieu sur place");
{
  const o = await ouvrir(ADMBZ, "#/comptes");
  const carte = await texte(o.page, "#cp-vendeurs");
  ok(/sur place, chez lui/.test(carte) && /n'a plus qu'à le valider/.test(carte),
    "la carte des vendeurs dit le chemin : sur place, puis le superadministrateur valide");
  await o.page.click("#cp-nouveau-vendeur");
  await pause(500);
  await o.page.fill("#nc-tel", "01 97 80 00 09");
  await o.page.fill("#nc-mdp", "essai-banc-1");
  await o.page.fill("#nc-nom", "Bazar Sena");
  await o.page.click("#nc-creer");
  await pause(1800);
  const fiche = o.ecrits.find((x) => /^POST profils/.test(x.quoi));
  ok(!!fiche && fiche.corps.role === "vendeur" && fiche.corps.actif === false && fiche.corps.id === NEUF,
    "le compte part INACTIF : le superadministrateur le validera");
  const feuille = await texte(o.page, "#feuille");
  ok(/Le lieu de Bazar Sena/.test(feuille), "la fiche de son lieu s'ouvre aussitôt (« Le lieu de Bazar Sena »)");
  ok(/Vous êtes chez lui \?/.test(feuille) && /Je suis chez lui : ma position/.test(feuille),
    "« Vous êtes chez lui ? » : le bouton de la position est là");
  ok(await o.page.evaluate(() => document.querySelector("#vl-nom").value) === "Bazar Sena",
    "le nom de son commerce est prérempli");
  await o.page.fill("#vl-adresse", "Missèbo, en face de la pharmacie");
  await o.page.click("#vl-ici");
  await pause(800);
  ok(/6\.37020, 2\.42890/.test(await texte(o.page, "#vl-etat")), "la position de SON téléphone devient celle du vendeur");
  await o.page.click("#vl-enregistrer");
  await pause(900);
  const lieu = o.ecrits.find((x) => x.quoi === "POST rpc/enregistrer_lieu_vendeur");
  ok(!!lieu && lieu.corps.cible === NEUF && lieu.corps.lieu.latitude === 6.3702 && lieu.corps.lieu.longitude === 2.4289 &&
     lieu.corps.lieu.adresse === "Missèbo, en face de la pharmacie",
    "le lieu s'enregistre : adresse et position, pour CE vendeur");
  sansErreur(o);
  await o.ctx.close();
}

titre("2. Il retrouve ses vendeurs en attente, avec leur lieu");
{
  const o = await ouvrir(ADMBZ, "#/comptes");
  const carte = await texte(o.page, "#cp-vendeurs");
  ok(/En attente de validation \(1\)/.test(carte) && /Pagnes Afi/.test(carte) && /Dantokpa, allée 4/.test(carte),
    "« En attente de validation (1) » : Pagnes Afi, et son adresse");
  ok(!/Chez Koffi/.test(carte), "pas le vendeur d'un autre administrateur");
  ok(!(await o.page.$("#cp-vendeurs [data-valider]")), "pas de bouton « Valider » : c'est au superadministrateur");
  await o.page.click('[data-lieu-vendeur="' + V1 + '"]');
  await pause(800);
  ok(/Le lieu de Pagnes Afi/.test(await texte(o.page, "#feuille")) &&
     await o.page.evaluate(() => document.querySelector("#vl-adresse").value) === "Dantokpa, allée 4",
    "« Son lieu » rouvre sa fiche, pour la corriger");
  sansErreur(o);
  await o.ctx.close();
}

titre("3. Le superadministrateur vérifie, puis valide");
{
  const o = await ouvrir(SUP, "#/vendeurs");
  const bloc = await texte(o.page, "#vv-a-valider");
  ok(/À valider \(2\)/.test(bloc) && /Pagnes Afi/.test(bloc) && /Chez Koffi/.test(bloc) && !/Tissus Ayi/.test(bloc),
    "« À valider (2) » en tête : les deux vendeurs créés sur place, pas celui en service");
  ok(/Créé par Admin BZ/.test(bloc) && /Dantokpa, allée 4/.test(bloc), "qui l'a créé, et son lieu");
  ok(/Position manquante/.test(bloc), "un lieu pas encore posé se voit");
  const ordre = await o.page.evaluate(() => [...document.querySelectorAll("#vv-liste .vv-vendeur strong")].map((x) => x.textContent));
  ok(ordre.indexOf("Tissus Ayi") === 2, "dans la liste, les vendeurs à valider passent devant (" + ordre.join(", ") + ")");
  ok(/À valider/.test(await texte(o.page, '[data-vendeur="' + V1 + '"]')), "leur pastille dit « À valider », pas « Inactif »");
  await o.page.click('#vv-a-valider [data-lieu="' + V1 + '"]');
  await pause(800);
  const feuille = await texte(o.page, "#feuille");
  ok(/Le lieu de Pagnes Afi/.test(feuille) && !/Vous êtes chez lui \?/.test(feuille),
    "« Voir son lieu » ouvre sa fiche (sans le mot pour l'administrateur sur place)");
  await o.page.evaluate(() => UI.fermerFeuille());
  await pause(400);
  await o.page.click('[data-valider-vendeur="' + V1 + '"]');
  await pause(900);
  const patch = o.ecrits.find((x) => x.quoi.startsWith("PATCH profils") && x.quoi.includes(V1));
  ok(!!patch && patch.corps.actif === true, "« Valider » l'active — la base prévient son créateur");
  sansErreur(o);
  await o.ctx.close();
}
{
  const o = await ouvrir(SUP, "#/vendeurs/" + V2);
  ok(/Le lieu de Chez Koffi/.test(await texte(o.page, "#feuille")),
    "la notification « Un vendeur à valider » ouvre son lieu, à vérifier");
  sansErreur(o);
  await o.ctx.close();
}

titre("4. Dans Comptes aussi, le superadministrateur les trouve « À valider »");
{
  const o = await ouvrir(SUP, "#/comptes");
  const bloc = await texte(o.page, "#cp-a-valider");
  ok(/À valider \(2\)/.test(bloc) && /Pagnes Afi/.test(bloc) && /Chez Koffi/.test(bloc) && /vérifiez d'abord son lieu/.test(bloc),
    "« À valider (2) » : les deux vendeurs, « vérifiez d'abord son lieu »");
  ok(!!(await o.page.$('#cp-a-valider [data-lieu-vendeur="' + V1 + '"]')) &&
     !!(await o.page.$('#cp-a-valider [data-valider="' + V1 + '"]')),
    "« Voir son lieu » et « Valider »");
  sansErreur(o);
  await o.ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mL'administrateur crée le vendeur sur place, avec son lieu ; le superadministrateur valide ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
