/* =========================================================
   Banc — des histogrammes qu'on sait lire (BIZZOO Personnel, 3.73.0)

   Statistiques → Commandes, « Commandes payées par jour » :
     1. un axe des valeurs gradué (0, la moitié, le haut), des repères ;
     2. le nombre au-dessus de chaque barre, la date dessous ;
     3. les jours sans commande comptent, à zéro (ils manquaient) ;
     4. un résumé : total, moyenne par jour, meilleur jour ;
     5. toucher une barre : le jour en toutes lettres, ses commandes, son
        montant ; « Montant » bascule le graphe en FCFA ;
   Statistiques → Revenus et résultat : un mois en perte descend sous la
   ligne du zéro, en rouge, avec sa valeur.

   La base est simulée : seules les réponses de Supabase sont jouées.
   ========================================================= */
const { chromium } = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default;
const BASE = (process.env.BANC_URL || "http://127.0.0.1:5191") + "/personnel/";

let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const plat = (t) => String(t || "").replace(/[  ]/g, " ").replace(/\s+/g, " ").trim();

/* Du 19 au 28 octobre : quatre jours sans commande (21, 23, 24, 27). */
const PAR_JOUR = [
  { jour: "2026-10-19", payees: 6, montant: 120000 }, { jour: "2026-10-20", payees: 2, montant: 30000 },
  { jour: "2026-10-22", payees: 14, montant: 410000 }, { jour: "2026-10-25", payees: 4, montant: 80000 },
  { jour: "2026-10-26", payees: 3, montant: 45000 }, { jour: "2026-10-28", payees: 1, montant: 15000 }];
const COMMANDES = { payees: 30, articles: 41, creees: 35, a_payer: 3, echouees: 2, revendeurs: 1, montant: 700000,
  panier_moyen: 23333, frais_livraison: 30000, remises: 0, benefice: 70000, reverse_boutiques: 600000,
  par_jour: PAR_JOUR, boutiques: [], produits: [] };
const MOIS = (mois, resultat) => ({ mois, commandes: 10, encaisse: 100000, reverse_boutiques: 80000, marge: 10000,
  frais_livraison: 5000, remises: 0, gains_livreurs: 4000, revenus: 11000, salaires: 30000, depenses: 2000, resultat });

const navigateur = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined, args: ["--no-sandbox"] });
const page = await navigateur.newPage({ viewport: { width: 390, height: 1400 }, serviceWorkers: "block" });
const erreurs = [];
page.on("pageerror", (e) => erreurs.push(e.message));
await page.addInitScript(() => {
  localStorage.setItem("bizzoo-personnel-session", JSON.stringify({ access_token: "jeton", refresh_token: "r",
    email: "awa@essai.bj", expire_a: Date.now() + 3600 * 1000 }));
});
const REPONSES = {
  etat_connexion: { equipe: false },
  rh_tableau_de_bord: { moi: { id: "e1", prenoms: "Awa", nom: "Essai", administration: true, ceo: true, profil: "Direction" } },
  rh_caisse_acces: null, rh_compteurs_solde: {}, rh_mes_menus: [], rh_suivi_alertes_nb: 0, rh_activation: null, rh_paie_a_jour: 0,
  rh_statistiques: { periode: { depuis: "2026-10-19", jusqu: "2026-10-28" }, droits: { argent: true, marge: true },
    commandes: COMMANDES },
  rh_finances: { periode: { depuis: "2026-08-01", jusqu: "2026-10-31" },
    revenus: [MOIS("2026-08-01", 25000), MOIS("2026-09-01", -18000), MOIS("2026-10-01", 52000)] },
};
await page.route(/supabase\.co\//, async (route) => {
  const u = new URL(route.request().url());
  const nom = (u.pathname.match(/\/rest\/v1\/rpc\/([a-z_0-9]+)/) || [])[1];
  const valeur = nom && nom in REPONSES ? REPONSES[nom] : (nom ? null : []);
  await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(valeur) });
});

titre("1-4. Commandes payées par jour : axe, valeurs, dates, jours vides, résumé");
await page.goto(BASE + "#/statistiques/commandes?du=2026-10-19&au=2026-10-28");
await page.waitForSelector(".graphe", { timeout: 8000 }).catch(() => {});
await page.waitForTimeout(500);
const g = await page.evaluate(() => {
  const c = document.querySelector(".graphe");
  if (!c) return null;
  return {
    titre: c.querySelector("h3").innerText,
    axe: [...c.querySelectorAll(".graphe-axe span")].map((s) => s.innerText),
    reperes: c.querySelectorAll(".graphe-ligne").length,
    colonnes: c.querySelectorAll(".graphe-colonne").length,
    valeurs: [...c.querySelectorAll(".graphe-colonne")].map((col) => (col.querySelector(".graphe-valeur") || {}).innerText || ""),
    dates: [...c.querySelectorAll(".graphe-date")].map((d) => d.innerText),
    resume: (c.querySelector(".graphe-resume") || {}).innerText || "",
    hauteurs: [...c.querySelectorAll(".graphe-barre")].map((b) => b.getBoundingClientRect().height),
  };
});
ok(g && /Commandes payées par jour/.test(g.titre), "le graphe est là");
ok(g && g.axe.join("|") === "0|10|20", "l'axe est gradué : 0, 10, 20 (" + (g && g.axe.join(", ")) + ")");
ok(g && g.reperes === 3, "trois lignes de repère");
ok(g && g.colonnes === 10, "dix jours, du 19 au 28 — les jours sans commande comptent (" + (g && g.colonnes) + ")");
ok(g && g.valeurs.join(",") === "6,2,,14,,,4,3,,1", "le nombre au-dessus de chaque barre ; rien sur un jour vide (" + (g && g.valeurs.join(",")) + ")");
ok(g && g.dates[0] === "19/10" && g.dates[9] === "28/10" && g.dates.filter(Boolean).length === 10, "chaque date sous sa barre");
ok(g && g.hauteurs[3] > g.hauteurs[0] && g.hauteurs[0] > g.hauteurs[1] && g.hauteurs[2] === 0,
  "les hauteurs suivent les nombres ; un jour vide n'a pas de barre");
ok(g && /Total : 30 commandes/.test(plat(g.resume)) && /moyenne : 3 par jour/.test(plat(g.resume)) &&
  /meilleur jour : 22\/10 \(14 commandes\)/.test(plat(g.resume)), "le résumé : total, moyenne, meilleur jour (" + plat(g && g.resume) + ")");

titre("5. Toucher une barre ; basculer en montant");
await page.locator(".graphe-colonne").nth(3).click();
await page.waitForTimeout(200);
let detail = plat(await page.locator(".graphe-detail").innerText());
ok(/Jeudi 22 octobre 2026/.test(detail) && /14 commandes payées/.test(detail) && /410 000/.test(detail),
  "le 22 : le jour en toutes lettres, 14 commandes, 410 000 FCFA (" + detail + ")");
ok(await page.locator(".graphe-colonne.choisie").count() === 1, "la barre touchée est marquée");
await page.locator(".graphe-colonne").nth(2).click();
await page.waitForTimeout(200);
detail = plat(await page.locator(".graphe-detail").innerText());
ok(/Mercredi 21 octobre 2026/.test(detail) && /aucune commande payée/.test(detail), "le 21 : « aucune commande payée »");
await page.getByRole("button", { name: "Montant" }).click();
await page.waitForTimeout(300);
const m = await page.evaluate(() => {
  const c = document.querySelector(".graphe");
  return { titre: c.querySelector("h3").innerText, axe: [...c.querySelectorAll(".graphe-axe span")].map((s) => s.innerText),
    valeur: (c.querySelectorAll(".graphe-colonne")[3].querySelector(".graphe-valeur") || {}).innerText || "",
    resume: (c.querySelector(".graphe-resume") || {}).innerText || "" };
});
ok(/Montant encaissé par jour/.test(m.titre), "« Montant » : le graphe passe en FCFA");
ok(plat(m.axe.join("|")) === "0|250 k|500 k", "l'axe en milliers : 0, 250 k, 500 k (" + plat(m.axe.join(", ")) + ")");
ok(plat(m.valeur) === "410 k", "la barre du 22 : 410 k");
ok(/Total : 700 000/.test(plat(m.resume)), "le résumé en FCFA");

titre("Revenus et résultat : un mois en perte sous la ligne du zéro");
await page.evaluate(() => { location.hash = "#/statistiques/revenus?du=2026-08-01&au=2026-10-31"; });
await page.waitForTimeout(1500);
const r = await page.evaluate(() => {
  const c = [...document.querySelectorAll(".graphe")].find((x) => /Résultat par mois/.test(x.querySelector("h3").innerText));
  if (!c) return null;
  return { axe: [...c.querySelectorAll(".graphe-axe span")].map((s) => s.innerText),
    zero: c.querySelectorAll(".graphe-ligne.zero").length,
    negatives: c.querySelectorAll(".graphe-barre.negative").length,
    valeurs: [...c.querySelectorAll(".graphe-valeur")].map((v) => v.innerText),
    dates: [...c.querySelectorAll(".graphe-date")].map((d) => d.innerText) };
});
ok(r && r.zero === 1 && r.negatives === 1, "la ligne du zéro, et une barre rouge sous elle");
ok(r && plat(r.axe.join("|")) === "−20 k|0|100 k", "l'axe va de −20 k à 100 k (" + (r && plat(r.axe.join(", "))) + ")");
ok(r && plat(r.valeurs.join("|")) === "25 k|−18 k|52 k", "chaque mois porte sa valeur, la perte en négatif");
ok(r && r.dates.every(Boolean), "chaque mois est nommé sous sa barre (" + (r && r.dates.join(", ")) + ")");
ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));

await navigateur.close();
console.log(echecs ? "\n" + echecs + " échec(s)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
