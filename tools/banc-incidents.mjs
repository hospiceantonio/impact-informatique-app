/* =========================================================
   Banc — le menu Incidents et la clôture automatique (Personnel, 3.69.0)

   Le menu Incidents : sa pastille, les incidents ouverts d'abord (tous,
   puis par filtre), « Signaler » par le numéro de la commande,
   « Résoudre ». Suivi → Réglages : le délai de la clôture automatique
   (vide : à la main). La fiche d'une commande clôturée par la base le
   dit. Une base d'avant (sans le réglage) : pas de cadre, pas d'erreur.

   La base est simulée : seules les réponses de Supabase sont jouées.

     PLAYWRIGHT=… CHROMIUM=… BANC_URL=http://127.0.0.1:5191 node tools/banc-incidents.mjs
     CAPTURES=<dossier> : une image du menu et du réglage.
   ========================================================= */
const { chromium } = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default;
const BASE = (process.env.BANC_URL || "http://127.0.0.1:5191") + "/personnel/";

let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");

const INCIDENTS = [
  { id: 11, type: "colis_abime", description: "Le carton est arrivé ouvert", cree_le: "2026-10-27T10:00:00Z",
    commande_id: "c-1", numero: "BZ-0101", client: "Sika", boutique: "Boutique A", livreur: "Koffi",
    auteur: "Awa Essai", resolu_le: null, resolution: "", resolu_par: "", cloturee: false },
  { id: 12, type: "retard", description: "Livreur bloqué au marché", cree_le: "2026-09-10T08:00:00Z",
    commande_id: "c-2", numero: "BZ-0102", client: "Rachidi", boutique: "Boutique B", livreur: null,
    auteur: "Awa Essai", resolu_le: null, resolution: "", resolu_par: "", cloturee: false },
  { id: 13, type: "adresse", description: "Adresse introuvable", cree_le: "2026-10-20T08:00:00Z",
    commande_id: "c-3", numero: "BZ-0103", client: "Mariam", boutique: "Boutique A", livreur: null,
    auteur: "Awa Essai", resolu_le: "2026-10-20T12:00:00Z", resolution: "Client rappelé", resolu_par: "Awa Essai", cloturee: true },
];
const appels = [];
let reglages = { vue_h: 2, preparation_h: 4, livraison_h: 24, confirmation_h: 24, cloture_auto_h: 24 };
const COMMANDE = { id: "c-3", numero: "BZ-0103", cree_le: "2026-10-20T07:00:00Z", paye_le: "2026-10-20T07:01:00Z",
  etat: "payee", source: "Depuis APP", client: { nom: "Mariam", tel: "0196700001", zone: "Akpakpa", adresse: "Akpakpa", zone_corrigee: false },
  lignes: [], articles: "", marchands: "", livreurs: "", frais: 1000, total: 6000, reste: 0, rang: 14, statut: "Clôturée",
  confirmation: "Oui", delai_h: 3, observations: "", incidents_ouverts: 0, cloturee_le: "2026-10-21T12:23:00Z", alertes: [] };

const REPONSES = {
  etat_connexion: { equipe: false },
  rh_tableau_de_bord: { moi: { id: "e1", prenoms: "Awa", nom: "Essai", administration: true, profil: "Administrateur" } },
  rh_caisse_acces: null, rh_compteurs_solde: {}, rh_mes_menus: ["suivi"], rh_suivi_alertes_nb: 0,
  rh_activation: null, rh_paie_a_jour: 0,
  rh_incidents_ouverts_nb: 2,
  rh_incidents_liste: { periode: { depuis: "2026-09-29", jusqu: "2026-10-28" }, incidents: INCIDENTS },
  rh_incident_ouvrir: 14, rh_incident_resoudre: null, rh_suivi_regler_cloture: null,
  rh_suivi: () => ({ periode: { depuis: "2026-10-28", jusqu: "2026-10-28" }, montants: true, reglages, commandes: [] }),
  rh_suivi_commande: () => ({ ...COMMANDE, montants: true, incidents: [], reclamations: [], refus: [],
    journal: [{ le: "2026-10-21T12:23:00Z", quoi: "suivi", valeur: "cloturee_auto" }] }),
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
  if (nom) appels.push({ nom, corps });
  const r = nom && nom in REPONSES ? REPONSES[nom] : (nom ? null : []);
  const valeur = typeof r === "function" ? r(corps) : r;
  await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(valeur) });
});
const texte = () => page.evaluate(() => document.body.innerText.replace(/\s+/g, " "));
const dernier = (nom) => [...appels].reverse().find((a) => a.nom === nom);

await page.goto(BASE + "#/incidents");
await page.waitForSelector(".liste .element", { timeout: 15000 });

titre("Le menu");
const lien = page.locator("#menu-lateral a[data-route='incidents']");
ok(await lien.count() === 1, "« Incidents » est au menu, à qui suit les commandes");
ok((await lien.innerText()).includes("2"), "sa pastille compte les incidents ouverts (2)");
const ordre = await page.$$eval("#menu-lateral a[data-route]", (a) => a.map((x) => x.dataset.route));
ok(ordre.indexOf("incidents") === ordre.indexOf("suivi") + 1, "juste sous « Suivi commandes »");

titre("La liste");
let elements = await page.$$eval(".liste .element", (e) => e.map((x) => x.innerText));
ok(elements.length === 2 && elements.every((t) => t.includes("Ouvert")), "par défaut : les 2 incidents ouverts (" + elements.length + ")");
ok(elements.some((t) => t.includes("BZ-0102")), "y compris l'ancien, signalé hors de la période");
ok(elements[0].includes("Colis abîmé") && elements[0].includes("Sika") && elements[0].includes("Boutique A"),
  "le type, le client, le marchand");
await page.selectOption("select[aria-label='État']", "");
elements = await page.$$eval(".liste .element", (e) => e.map((x) => x.innerText));
ok(elements.length === 3, "« Tous » : les 3, le résolu compris");
ok(elements.some((t) => t.includes("Résolu le") && t.includes("Client rappelé")), "le résolu dit comment, et par qui");
await page.selectOption("select[aria-label='État']", "resolus");
ok(await page.locator(".liste .element").count() === 1, "« Résolus » : le seul résolu");
await page.selectOption("select[aria-label='État']", "");
await page.fill("input[aria-label='Rechercher']", "marché");
elements = await page.$$eval(".liste .element", (e) => e.map((x) => x.innerText));
ok(elements.length === 1 && elements[0].includes("BZ-0102"), "la recherche lit la description");
await page.fill("input[aria-label='Rechercher']", "");
await page.selectOption("select[aria-label='Type']", "adresse");
ok(await page.locator(".liste .element").count() === 1, "le filtre par type");
await page.selectOption("select[aria-label='Type']", "");
await page.selectOption("select[aria-label='État']", "ouverts");
const href = await page.locator(".liste .element a").first().getAttribute("href");
ok(href === "#/suivi/commande/c-1", "un lien mène à la fiche de la commande");
if (process.env.CAPTURES) await page.screenshot({ path: process.env.CAPTURES + "/incidents.png" });

titre("Signaler, résoudre");
await page.getByRole("button", { name: "Signaler un incident" }).click();
await page.waitForSelector("dialog[open]");
await page.fill("dialog [name=commande]", "bz-0105");
await page.selectOption("dialog [name=type]", "paiement");
await page.fill("dialog [name=description]", "Le client dit avoir déjà payé");
await page.click("dialog button[type=submit]");
await page.waitForFunction(() => !document.querySelector("dialog[open]"));
await page.waitForTimeout(300);
const ouvert = dernier("rh_incident_ouvrir");
ok(ouvert && ouvert.corps.commande === "bz-0105" && ouvert.corps.type === "paiement"
  && ouvert.corps.description === "Le client dit avoir déjà payé", "« Signaler » envoie le numéro saisi, le type, la description");
await page.waitForSelector(".liste .element");
await page.locator(".liste .element").first().getByRole("button", { name: "Résoudre" }).click();
await page.waitForSelector("dialog[open]");
await page.fill("dialog [name=motif]", "Colis remplacé");
await page.click("dialog button[type=submit]");
await page.waitForTimeout(400);
const resolu = dernier("rh_incident_resoudre");
ok(resolu && resolu.corps.incident === 11 && resolu.corps.resolution === "Colis remplacé", "« Résoudre » envoie l'incident et la résolution");

titre("Le réglage de la clôture");
await page.goto(BASE + "#/suivi/reglages");
await page.waitForFunction(() => document.body.innerText.includes("Clôture automatique"));
const champ = page.getByLabel("Délai (en heures)");
ok(await champ.inputValue() === "24", "le délai en place : 24 heures");
await champ.fill("");
await page.locator("form", { hasText: "Clôture automatique" }).getByRole("button", { name: "Enregistrer" }).click();
await page.waitForTimeout(300);
ok(dernier("rh_suivi_regler_cloture") && dernier("rh_suivi_regler_cloture").corps.heures === null, "vide : à la main (null)");
await champ.fill("0");
await page.locator("form", { hasText: "Clôture automatique" }).getByRole("button", { name: "Enregistrer" }).click();
await page.waitForTimeout(300);
ok(dernier("rh_suivi_regler_cloture").corps.heures === 0, "0 : tout de suite");
if (process.env.CAPTURES) {
  await champ.fill("24");
  await page.locator("form", { hasText: "Clôture automatique" }).screenshot({ path: process.env.CAPTURES + "/reglage-cloture.png" });
}

titre("Une base d'avant");
reglages = { vue_h: 2, preparation_h: 4, livraison_h: 24, confirmation_h: 24 };
await page.goto(BASE + "#/suivi/bilan");
await page.waitForFunction(() => !document.body.innerText.includes("Délais des alertes"));
await page.goto(BASE + "#/suivi/reglages");
await page.waitForFunction(() => document.body.innerText.includes("Délais des alertes"));
await page.waitForTimeout(200);
ok(await page.locator("form h2", { hasText: "Clôture automatique" }).count() === 0, "sans le réglage en base : pas de cadre");

titre("La fiche");
await page.goto(BASE + "#/suivi/commande/c-3");
await page.waitForFunction(() => document.body.innerText.includes("Passée le"));
const fiche = await texte();
ok(/Clôturée automatiquement le/.test(fiche), "la fiche dit « Clôturée automatiquement le … »");
ok(/Chronologie.*Clôturée automatiquement/.test(fiche), "et la chronologie aussi");

ok(erreurs.length === 0, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs.join(" ; ") : ""));
await navigateur.close();
console.log(echecs ? "\n" + echecs + " échec(s)" : "\nTout passe.");
process.exit(echecs ? 1 : 0);
