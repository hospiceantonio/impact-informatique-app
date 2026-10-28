/* =========================================================
   Banc — la colonne « Source » du suivi des commandes (Personnel, 3.68.0)

   Une commande passée dans l'application se lit « Depuis APP », une
   commande prise sur WhatsApp (« Faire livrer ») « Par whatsapp » : dans
   le tableau, au filtre, sur la fiche. Une base d'avant ne rend pas la
   source : la commande se lit alors « Depuis APP ».

   La base est simulée : seules les réponses de Supabase sont jouées.

     PLAYWRIGHT=… CHROMIUM=… BANC_URL=http://127.0.0.1:5191 node tools/banc-suivi-source.mjs
   ========================================================= */
const { chromium } = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default;
const BASE = (process.env.BANC_URL || "http://127.0.0.1:5191") + "/personnel/";

let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");

const ligne = (id, boutique) => ({ id, commande_id: "", nom: "Casque", code: "", quantite: 1, prix: 12000,
  boutique_id: "bou_a", boutique, boutique_tel: "0196000001", livreur: null, livreur_tel: "", livreur_id: null,
  rang: 2, statut: "Vue par le marchand", terrain: "", terrain_motif: "", vue_le: "2026-10-28T09:05:00Z",
  remise_le: null, confirme_le: null });
const commande = (id, numero, source, minute) => {
  const c = { id, numero, cree_le: "2026-10-28T09:" + minute + ":00Z", paye_le: "2026-10-28T09:" + minute + ":30Z",
    etat: "payee", client: { nom: "Client " + numero, tel: "0196700099", zone: "Fidjrossè", adresse: "Fidjrossè", zone_corrigee: false },
    lignes: [ligne("l-" + id, "Boutique A")], articles: "1 × Casque", marchands: "Boutique A / 0196000001", livreurs: "",
    frais: 1500, total: 13500, reste: 0, rang: 2, statut: "Vue par le marchand", confirmation: "Non", delai_h: null,
    observations: "", incidents_ouverts: 0, cloturee_le: null, alertes: [] };
  if (source !== undefined) c.source = source;
  return c;
};
const COMMANDES = [
  commande("c-app", "BZ-0101", "Depuis APP", "10"),
  commande("c-wa", "BZ-0102", "Par whatsapp", "20"),
  commande("c-avant", "BZ-0103", undefined, "30"), // une base d'avant : pas de « source »
];

const REPONSES = {
  etat_connexion: { equipe: false },
  rh_tableau_de_bord: { moi: { id: "e1", prenoms: "Awa", nom: "Essai", administration: true, profil: "Administrateur" } },
  rh_caisse_acces: null, rh_compteurs_solde: {}, rh_mes_menus: ["suivi"], rh_suivi_alertes_nb: 0,
  rh_activation: null, rh_paie_a_jour: 0,
  rh_suivi: { periode: { depuis: "2026-10-22", jusqu: "2026-10-28" }, montants: true,
    reglages: { vue_h: 2, preparation_h: 4, livraison_h: 24, confirmation_h: 24 }, commandes: COMMANDES },
  rh_suivi_commande: (corps) => ({ ...COMMANDES.find((c) => c.id === corps.commande), montants: true,
    journal: [], incidents: [], reclamations: [], refus: [] }),
};

const navigateur = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined, args: ["--no-sandbox"] });
const page = await navigateur.newPage({ viewport: { width: 1280, height: 900 }, serviceWorkers: "block" });
const erreurs = [];
page.on("pageerror", (e) => erreurs.push(e.message));
await page.addInitScript(() => {
  localStorage.setItem("bizzoo-personnel-session", JSON.stringify({ access_token: "jeton", refresh_token: "r",
    email: "awa@essai.bj", expire_a: Date.now() + 3600 * 1000 }));
});
await page.route(/supabase\.co\//, async (route) => {
  const u = new URL(route.request().url());
  const nom = (u.pathname.match(/\/rest\/v1\/rpc\/([a-z_0-9]+)/) || [])[1];
  let corps = {};
  try { corps = JSON.parse(route.request().postData() || "{}"); } catch (_) { /* vide */ }
  const r = nom && nom in REPONSES ? REPONSES[nom] : (nom ? null : []);
  const valeur = typeof r === "function" ? r(corps) : r;
  await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(valeur) });
});

await page.goto(BASE + "#/suivi");
await page.waitForSelector("table thead th", { timeout: 15000 });

titre("Le tableau");
const entetes = await page.$$eval("table thead th", (t) => t.map((x) => x.textContent.trim()));
const iDate = entetes.findIndex((t) => /Date/.test(t));
ok(entetes[iDate + 1] === "Source", "une colonne « Source », juste après la date (" + entetes.join(" | ") + ")");
const sourceDe = (numero) => page.$$eval("table tbody tr", (lignes, [num, i]) => {
  const tr = lignes.find((l) => l.textContent.includes(num));
  return tr ? tr.children[i].textContent.trim() : null;
}, [numero, iDate + 1]);
ok(await sourceDe("BZ-0101") === "Depuis APP", "une commande de l'application : « Depuis APP »");
ok(await sourceDe("BZ-0102") === "Par whatsapp", "une commande WhatsApp : « Par whatsapp »");
ok(await sourceDe("BZ-0103") === "Depuis APP", "une base d'avant, sans source : « Depuis APP »");
ok(await page.$$eval("table tbody .source-whatsapp", (x) => x.length) === 1, "« Par whatsapp » se distingue à l'œil");

titre("Le filtre");
const choix = page.locator("select[aria-label='Source']");
ok(await choix.count() === 1, "un filtre « Source »");
await choix.selectOption("Par whatsapp");
let numeros = await page.$$eval("table tbody tr", (l) => l.map((x) => x.textContent));
ok(numeros.length === 1 && numeros[0].includes("BZ-0102"), "« Par whatsapp » : la seule commande WhatsApp (" + numeros.length + ")");
await choix.selectOption("Depuis APP");
numeros = await page.$$eval("table tbody tr", (l) => l.map((x) => x.textContent));
ok(numeros.length === 2 && !numeros.some((t) => t.includes("BZ-0102")), "« Depuis APP » : les deux autres (" + numeros.length + ")");
await choix.selectOption("");
if (process.env.CAPTURES) await page.screenshot({ path: process.env.CAPTURES + "/suivi-source.png" });

titre("La fiche");
await page.goto(BASE + "#/suivi/commande/c-wa");
await page.waitForSelector("h2", { timeout: 15000 });
await page.waitForFunction(() => document.body.innerText.includes("Passée le"));
const fiche = await page.evaluate(() => document.body.innerText.replace(/\s+/g, " "));
ok(/Source Par whatsapp/.test(fiche), "la fiche d'une commande WhatsApp dit « Par whatsapp »");
await page.goto(BASE + "#/suivi/commande/c-app");
await page.waitForFunction(() => document.body.innerText.includes("BZ-0101") && document.body.innerText.includes("Passée le"));
ok(/Source Depuis APP/.test(await page.evaluate(() => document.body.innerText.replace(/\s+/g, " "))),
  "celle d'une commande de l'application, « Depuis APP »");

ok(erreurs.length === 0, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs.join(" ; ") : ""));
await navigateur.close();
console.log(echecs ? "\n" + echecs + " échec(s)" : "\nTout passe.");
process.exit(echecs ? 1 : 0);
