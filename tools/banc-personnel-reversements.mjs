/* =========================================================
   Banc — les reversements dans BIZZOO Personnel (3.73.0)

   Le menu « Reversements » : au CEO et au profil « Comptabilité » seuls
   (rh_reversements_acces), avec sa pastille — un superadministrateur
   qui n'est ni l'un ni l'autre ne l'a pas. L'écran : les demandes des boutiques, des livreurs et des
   vendeurs ensemble, à traiter d'abord ; le nom du compte MoMo d'un
   livreur (et l'écart avec celui qu'il a donné) ; « Envoyé » avec la
   référence, « Refuser » avec un motif, chacun par la bonne fonction.
   Le nom MoMo vient de noms_momo. Un autre compte n'a ni le menu ni
   l'écran.

   La base est simulée : seules les réponses de Supabase sont jouées.
   ========================================================= */
const { chromium } = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default;
const BASE = (process.env.BANC_URL || "http://127.0.0.1:5191") + "/personnel/";

let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");

const L1 = "11110000-0000-0000-0000-00000000000a";
const BOUTIQUES = [
  { id: 1, boutique_id: "bou_a", nom_boutique: "Alpha", montant: 12000, tel: "0196000001", reseau: "MTN", titulaire: "Alpha SARL",
    etat: "en_attente", demande_par: "Chef Alpha", demande_le: "2026-10-31T10:00:00Z", decide_par: "", decide_le: null,
    reference: "", motif: "", devise: "FCFA" },
  { id: 2, boutique_id: "bou_b", nom_boutique: "Bêta", montant: 5000, tel: "0196000002", reseau: "MOOV", titulaire: "",
    etat: "valide", demande_par: "Chef Bêta", demande_le: "2026-10-20T10:00:00Z", decide_par: "Sup", decide_le: "2026-10-21T10:00:00Z",
    reference: "MP-778899", motif: "", devise: "FCFA" }];
const LIVREURS = [
  { id: 7, livreur_id: L1, nom_livreur: "Rohim", montant: 1500, tel: "0167332135", reseau: "MTN", titulaire: "Jean Autre",
    etat: "en_attente", demande_le: "2026-10-31T11:00:00Z", decide_par: "", decide_le: null, reference: "", motif: "" }];
const VENDEURS = [
  { id: 9, vendeur_id: "v1", nom_vendeur: "AZERTY", montant: 3283, tel: "0195943189", reseau: "MOOV", titulaire: "Lawani",
    etat: "en_attente", demande_le: "2026-10-30T19:02:00Z", decide_par: "", decide_le: null, reference: "", motif: "" }];

async function ouvrir(acces, superadmin = false) {
  const appels = [];
  const REPONSES = {
    etat_connexion: { equipe: false },
    rh_tableau_de_bord: { moi: { id: "e1", prenoms: "Awa", nom: "Essai", administration: true, profil: "Administrateur", super: superadmin } },
    rh_caisse_acces: null, rh_compteurs_solde: {}, rh_mes_menus: [], rh_suivi_alertes_nb: 0, rh_activation: null, rh_paie_a_jour: 0,
    rh_reversements_acces: acces,
    reversements_liste: acces || superadmin ? BOUTIQUES : [], reversements_livreurs_liste: acces || superadmin ? LIVREURS : [],
    reversements_vendeurs_liste: acces || superadmin ? VENDEURS : [],
    noms_momo: acces ? [{ id: L1, momo_nom: "ROHIM KOFFI" }] : [],
    decider_reversement: "valide", decider_reversement_livreur: "valide", decider_reversement_vendeur: "refuse",
    /* (3.81.0) Les commandes d'une demande. */
    reversement_operations: { non_rattache: 0, commandes: [
      { commande_id: "cmd-1", numero: "BZ-000101", client: "Client Test", paye_le: "2026-11-01T10:00:00Z",
        part: 8000, couvert: 8000, paiement: "feexpay", transaction: "FX-778899", confirme_par: "",
        alertes: ["Le nom ou la note du client parle de test"] }] },
  };
  const navigateur = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined, args: ["--no-sandbox"] });
  const page = await navigateur.newPage({ viewport: { width: 1280, height: 1000 }, serviceWorkers: "block" });
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
    let valeur = nom && nom in REPONSES ? REPONSES[nom] : (nom ? null : []);
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(valeur) });
  });
  await page.goto(BASE + "#/reversements");
  await page.waitForTimeout(2500);
  return { navigateur, page, erreurs, appels };
}

titre("1. La comptabilité (ou le CEO) : le menu, la pastille, les demandes");
{
  const { navigateur, page, erreurs, appels } = await ouvrir(true);
  const nm = appels.find((x) => x.nom === "noms_momo");
  ok(nm && JSON.stringify(nm.corps.ids) === JSON.stringify([L1]), "le nom MoMo : demandé par noms_momo, pour le seul livreur");
  const lien = page.locator("#menu-lateral a[data-route='reversements']");
  ok(await lien.count() === 1, "« Reversements » est au menu");
  ok((await lien.innerText()).includes("3"), "sa pastille : 3 demandes à traiter");
  const elements = await page.$$eval(".element.reversement", (e) => e.map((x) => x.innerText.replace(/\s+/g, " ")));
  ok(elements.length === 3, "à traiter, par défaut : la boutique, le livreur, le vendeur (" + elements.length + ")");
  ok(elements.some((t) => /Boutique — Alpha/.test(t)) && elements.some((t) => /Livreur — Rohim/.test(t)) &&
     elements.some((t) => /Vendeur — AZERTY/.test(t) && /MOOV 0195943189 \(Lawani\)/.test(t)),
    "chacun avec son demandeur et son numéro");
  /* (3.81.0) D'où vient l'argent : sous chaque demande à traiter. */
  ok(appels.filter((x) => x.nom === "reversement_operations").length === 3 &&
     elements.every((t) => /BZ-000101/.test(t) && /FeexPay — référence FX-778899/.test(t) && /parle de test/.test(t)),
    "sous chaque demande à traiter : ses commandes, la référence FeexPay, et ce qui doit faire vérifier");
  const rohim = elements.find((t) => /Rohim/.test(t)) || "";
  ok(/ROHIM KOFFI/.test(rohim) && /n'est pas le même nom/.test(rohim), "le livreur : le nom du compte MoMo, et l'écart signalé");
  await page.selectOption("select[aria-label='État']", "traites");
  await page.waitForTimeout(200);
  const traites = await page.$$eval(".element.reversement", (e) => e.map((x) => x.innerText.replace(/\s+/g, " ")));
  ok(traites.length === 1 && /MP-778899/.test(traites[0]), "« Déjà traités » : l'envoi à Bêta, avec sa référence");
  await page.selectOption("select[aria-label='État']", "en_attente");
  await page.waitForTimeout(200);

  /* « Envoyé » pour le livreur : la référence, et la bonne fonction. */
  await page.locator(".element.reversement", { hasText: "Rohim" }).getByRole("button", { name: "Envoyé" }).click();
  await page.waitForSelector("dialog input[name=reference]");
  await page.fill("dialog input[name=reference]", "MP-123456");
  await page.click("dialog button[type=submit]");
  await page.waitForTimeout(800);
  const a = [...appels].reverse().find((x) => x.nom === "decider_reversement_livreur");
  ok(a && a.corps.cible === 7 && a.corps.accord === true && a.corps.reference === "MP-123456",
    "« Envoyé » : decider_reversement_livreur(7, oui, MP-123456)");
  /* « Refuser » pour le vendeur : un motif. */
  await page.locator(".element.reversement", { hasText: "AZERTY" }).getByRole("button", { name: "Refuser" }).click();
  await page.waitForSelector("dialog textarea[name=motif]");
  await page.fill("dialog textarea[name=motif]", "Numéro au nom d'un autre");
  await page.click("dialog button[type=submit]");
  await page.waitForTimeout(800);
  const r = [...appels].reverse().find((x) => x.nom === "decider_reversement_vendeur");
  ok(r && r.corps.cible === 9 && r.corps.accord === false && r.corps.motif === "Numéro au nom d'un autre",
    "« Refuser » : decider_reversement_vendeur(9, non, le motif)");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await navigateur.close();
}

titre("2. Un autre compte — même superadministrateur : ni le menu, ni l'écran");
{
  const { navigateur, page, erreurs } = await ouvrir(false, true);
  ok(await page.locator("#menu-lateral a[data-route='reversements']").count() === 0, "pas de menu « Reversements »");
  ok(/n'y a pas accès|Réservé au CEO/.test(await page.evaluate(() => document.body.innerText)) &&
     await page.locator(".element.reversement").count() === 0, "l'adresse tapée à la main : « votre compte n'y a pas accès »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await navigateur.close();
}

console.log(echecs ? "\n" + echecs + " échec(s)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
