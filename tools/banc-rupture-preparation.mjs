/* =========================================================
   Banc — trois demandes de l'équipe (3.75.0), côté écrans

     1. LE CLIENT revient payer une commande en attente dont un produit est
        parti en rupture : le reçu le dit (« Rupture de stock », la liste),
        plus de bouton « Payer » ; « Refaire mon panier sans ce produit »
        remet le reste au panier. Si la base ne l'a pas encore dit, c'est
        la fonction de paiement qui refuse, et le reçu passe à la rupture.
     2. PERSONNEL, Suivi des commandes : la colonne « Préparation (vue →
        préparée) » — 14 min dans le délai, 34 min en retard (> 20 min),
        « en cours », et le détail par marchand.

   La base est simulée : seules les réponses de Supabase sont jouées.

     PLAYWRIGHT=… CHROMIUM=… BANC_URL=http://127.0.0.1:5191 node tools/banc-rupture-preparation.mjs
   ========================================================= */
const { chromium } = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default;
const BASE = process.env.BANC_URL || "http://127.0.0.1:5191";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined, args: ["--no-sandbox"] });
const plat = (s) => String(s || "").replace(/[  ]/g, " ").replace(/\s+/g, " ").trim();

/* ================================================================
   1. Le client
   ================================================================ */
const COMMANDE = { id: "cmd_r", numero: "BZ-000077", total: 17000, devise: "FCFA", etat: "a_payer",
  client: { nom: "Koffi", tel: "0197000000", indicatif: "229", adresse: "Cotonou" },
  boutiques: [{ id: "bou_a", nom: "Alpha", montant: 17000,
    lignes: [{ nom: "Casque", prix: 7000, quantite: 2 }, { nom: "Câble", prix: 1000, quantite: 3 }] }] };
const BOUTIQUE = { id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech", icone: "magasin",
  couleur: "#0047D9", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 };
const produit = (id, nom, prix, stock) => ({ id, boutique_id: "bou_a", nom, code: "", prix,
  categorie_id: "cat_hightech", sous_categorie_id: "sc_x", stock, disponible: true, images: [],
  cree_le: "2026-09-01T08:00:00Z", modifie_le: "2026-09-01T08:00:00Z" });
const PRODUITS = [produit("p_casque", "Casque", 7000, 1), produit("p_cable", "Câble", 1000, 50)];
const MANQUANTS = { manquants: [{ produit_id: "p_casque", nom: "Casque", demande: 2, reste: 1 }],
  autres: [{ produit_id: "p_cable", quantite: 3 }] };

async function ouvrirClient({ manquants = MANQUANTS, payer = null } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1000 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((c) => {
    try {
      localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
      localStorage.setItem("bizzoo-commandes", JSON.stringify([c]));
      localStorage.setItem("bizzoo-coordonnees", JSON.stringify({ nom: "Koffi", tel: "0197000000", indicatif: "229", adresse: "Cotonou" }));
    } catch (_) { /* vide */ }
  }, COMMANDE);
  const serveur = { appels: [], manquants: [] };
  await page.route("**/functions/v1/feexpay", (route) => {
    const corps = JSON.parse(route.request().postData() || "{}");
    serveur.appels.push(corps);
    if (corps.action === "payer" && payer) {
      return route.fulfill({ status: payer.statut, contentType: "application/json", body: JSON.stringify(payer.corps) });
    }
    /* Aucune demande en cours : le reçu propose de payer. */
    return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ etat: "a_payer", raison: "aucun paiement ouvert" }) });
  });
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/manquants_commande")) {
      serveur.manquants.push(JSON.parse(route.request().postData() || "{}"));
      return d(manquants);
    }
    if (c.startsWith("rpc/suivre_commande")) return d({ etat: "a_payer", remarque: "" });
    if (c.startsWith("rpc/")) return d([]);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: true, fournisseur: "feexpay", cle_publique: "", bac_a_sable: false }]);
    if (c.startsWith("produits")) return d(PRODUITS);
    if (c.startsWith("boutiques")) return d([BOUTIQUE]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/client/index.html#/commande/cmd_r", { waitUntil: "domcontentloaded" });
  return { page, ctx, erreurs, serveur };
}
const etatCarte = (page) => page.evaluate(() => (document.querySelector("#re-attente") || {}).dataset?.etat || "");
const attendre = (page, etat) => page.waitForFunction((e) => (document.querySelector("#re-attente") || {}).dataset?.etat === e,
  etat, { timeout: 8000 }).then(() => true, () => false);

titre("1. Commande en attente, un produit parti en rupture : le reçu le dit");
{
  const { page, ctx, erreurs, serveur } = await ouvrirClient();
  ok(await attendre(page, "rupture"), "la carte passe à « rupture » (" + await etatCarte(page) + ")");
  const texte = plat(await page.textContent("#re-attente").catch(() => ""));
  ok(/Rupture de stock\./.test(texte) && /Ce produit n'est plus disponible depuis votre commande : elle ne peut plus être payée/.test(texte),
    "« Rupture de stock. Ce produit n'est plus disponible… ne peut plus être payée »");
  ok(/Casque — plus que 1 en stock \(2 commandés\)/.test(texte), "le produit, et ce qui reste : « Casque — plus que 1 en stock (2 commandés) »");
  ok(!(await page.$('#re-attente [data-attente="payer"]')), "plus de bouton « Payer »");
  ok(serveur.manquants.some((m) => m.cible === "cmd_r" && m.tel === "0197000000"),
    "la base est interrogée avec la commande et le numéro du client");
  await page.click('#re-attente [data-attente="refaire"]');
  await page.waitForTimeout(800);
  const panier = await page.evaluate(() => JSON.parse(localStorage.getItem("bizzoo-panier") || "[]"));
  const q = (id) => (panier.find((l) => l.produitId === id) || {}).quantite || 0;
  ok(q("p_cable") === 3 && q("p_casque") === 1,
    "« Refaire mon panier sans ce produit » : 3 câbles, et le casque qui reste (" + JSON.stringify(panier) + ")");
  ok(/#\/panier$/.test(page.url()), "et l'on arrive au panier");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("2. La base ne l'a pas encore dit : la fonction de paiement refuse, le reçu suit");
{
  const ERREUR = "Rupture de stock : « Casque » n'est plus disponible. Cette commande ne peut plus être payée : refaites votre panier sans ce produit.";
  let premier = true;
  const { page, ctx, erreurs, serveur } = await ouvrirClient({
    manquants: { manquants: [], autres: [] },
    payer: { statut: 409, corps: { erreur: ERREUR, rupture: true, manquants: [{ produit_id: "p_casque", nom: "Casque", demande: 2, reste: 0 }] } } });
  ok(await attendre(page, "rien"), "aucune rupture connue : « Payer maintenant » (" + await etatCarte(page) + ")");
  await page.click('#co-operateurs [data-reseau="MTN"]').catch(() => {});
  await page.fill("#co-mm-tel", "97 00 00 01").catch(() => {});
  await page.click('#re-attente [data-attente="payer"]');
  ok(await attendre(page, "rupture"), "la fonction de paiement répond « rupture » : le reçu passe à la rupture");
  const toast = plat(await page.textContent("#toasts").catch(() => ""));
  ok(/Rupture de stock : « Casque » n'est plus disponible/.test(toast), "et le dit tout de suite (« " + toast.slice(0, 80) + "… »)");
  ok(/Casque — en rupture de stock/.test(plat(await page.textContent("#re-attente"))), "« Casque — en rupture de stock »");
  ok(serveur.appels.some((a) => a.action === "payer"), "la demande est bien partie à la fonction (qui a refusé)");
  premier = false;
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("3. Rien ne manque : le reçu propose de payer, comme avant");
{
  const { page, ctx } = await ouvrirClient({ manquants: { manquants: [], autres: [] } });
  ok(await attendre(page, "rien"), "« Payer maintenant »");
  await page.waitForTimeout(600);
  ok(await etatCarte(page) === "rien" && !!(await page.$('#re-attente [data-attente="payer"]')), "le bouton « Payer maintenant » reste");
  await ctx.close();
}

/* ================================================================
   2. Personnel — le temps de préparation
   ================================================================ */
const ligne = (id, boutique, extra = {}) => ({ id, commande_id: "", nom: "Casque", code: "", quantite: 1, prix: 12000,
  boutique_id: "bou_" + boutique, boutique, boutique_tel: "", livreur: null, livreur_tel: "", livreur_id: null,
  rang: 3, statut: "Commande préparée", terrain: "", terrain_motif: "", vue_le: "2026-11-03T09:00:00Z",
  preparee_le: "2026-11-03T09:14:00Z", remise_le: null, confirme_le: null, ...extra });
const il_y_a = (min) => new Date(Date.now() - min * 60000).toISOString();
const commande = (id, numero, preparation, extra = {}) => ({ id, numero, cree_le: "2026-11-03T08:55:00Z", paye_le: "2026-11-03T08:56:00Z",
  etat: "payee", client: { nom: "Client " + numero, tel: "0196700099", zone: "Akpakpa", adresse: "Akpakpa", zone_corrigee: false },
  lignes: [ligne("l-" + id, "Alpha")], articles: "1 × Casque", marchands: "Alpha", livreurs: "",
  frais: 1000, total: 13000, reste: 0, rang: 3, statut: "Commande préparée", confirmation: "Non", delai_h: null,
  observations: "", incidents_ouverts: 0, cloturee_le: null, alertes: [], preparation, preparation_seuil_min: 20, ...extra });
const COMMANDES = [
  commande("c-ok", "BZ-0201", [{ boutique: "Alpha", vue_le: "2026-11-03T09:00:00Z", preparee_le: "2026-11-03T09:14:00Z", minutes: 14 }]),
  commande("c-lent", "BZ-0202", [{ boutique: "Alpha", vue_le: "2026-11-03T09:00:00Z", preparee_le: "2026-11-03T09:34:00Z", minutes: 34 }]),
  commande("c-cours", "BZ-0203", [{ boutique: "Alpha", vue_le: il_y_a(8), preparee_le: null, minutes: null }], { rang: 2, statut: "Confirmée" }),
  commande("c-deux", "BZ-0204", [{ boutique: "Alpha", vue_le: "2026-11-03T09:00:00Z", preparee_le: "2026-11-03T09:12:00Z", minutes: 12 },
                                 { boutique: "Bêta", vue_le: null, preparee_le: null, minutes: null }]),
  commande("c-avant", "BZ-0205", undefined, { preparation_seuil_min: undefined }),
];
const REPONSES = {
  etat_connexion: { equipe: false },
  rh_tableau_de_bord: { moi: { id: "e1", prenoms: "Awa", nom: "Essai", administration: true, profil: "Administrateur" } },
  rh_caisse_acces: null, rh_compteurs_solde: {}, rh_mes_menus: ["suivi"], rh_suivi_alertes_nb: 0,
  rh_activation: null, rh_paie_a_jour: 0,
  rh_suivi: { periode: { depuis: "2026-10-28", jusqu: "2026-11-03" }, montants: true,
    reglages: { vue_h: 2, preparation_min: 20, livraison_h: 24, confirmation_h: 24 }, commandes: COMMANDES },
};
titre("4. Personnel : le temps de préparation de chaque marchand");
{
  const page = await nav.newPage({ viewport: { width: 1400, height: 900 }, serviceWorkers: "block" });
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(() => {
    localStorage.setItem("bizzoo-personnel-session", JSON.stringify({ access_token: "jeton", refresh_token: "r",
      email: "awa@essai.bj", expire_a: Date.now() + 3600 * 1000 }));
  });
  await page.route(/supabase\.co\//, async (route) => {
    const u = new URL(route.request().url());
    const nom = (u.pathname.match(/\/rest\/v1\/rpc\/([a-z_0-9]+)/) || [])[1];
    const r = nom && nom in REPONSES ? REPONSES[nom] : (nom ? null : []);
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(r) });
  });
  await page.goto(BASE + "/personnel/#/suivi");
  await page.waitForSelector("table thead th", { timeout: 15000 });
  const entetes = await page.$$eval("table thead th", (t) => t.map((x) => x.textContent.trim()));
  const i = entetes.findIndex((t) => /^Préparation \(vue → préparée\)/.test(t));
  ok(i > 0, "une colonne « Préparation (vue → préparée) » (" + entetes.join(" | ") + ")");
  const cellule = (numero) => page.$$eval("table tbody tr", (lignes, [num, k]) => {
    const tr = lignes.find((l) => l.textContent.includes(num));
    return tr ? { texte: tr.children[k].textContent.replace(/\s+/g, " ").trim(),
                  rouge: !!tr.children[k].querySelector('[style*="rouge"]') } : null;
  }, [numero, i]);
  const ok14 = await cellule("BZ-0201");
  ok(ok14 && ok14.texte === "14 min" && !ok14.rouge, "préparée en 14 min : « 14 min », dans le délai (" + JSON.stringify(ok14) + ")");
  const lent = await cellule("BZ-0202");
  ok(lent && /34 min ⚠ > 20 min/.test(lent.texte) && lent.rouge, "34 min : « 34 min ⚠ > 20 min », en rouge (" + JSON.stringify(lent) + ")");
  const cours = await cellule("BZ-0203");
  ok(cours && /^en cours · (8|9) min$/.test(cours.texte), "vue il y a 8 min, pas encore préparée : « en cours · 8 min » (" + JSON.stringify(cours) + ")");
  const deux = await cellule("BZ-0204");
  ok(deux && /Alpha : 12 min/.test(deux.texte) && /Bêta : pas encore vue/.test(deux.texte),
    "deux marchands : « Alpha : 12 min », « Bêta : pas encore vue » (" + JSON.stringify(deux) + ")");
  const avant = await cellule("BZ-0205");
  ok(avant && avant.texte === "—", "une base d'avant, sans la donnée : « — »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await page.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mRupture dite au client, temps de préparation suivi ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
