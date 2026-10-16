/* =========================================================
   Le paiement qui n'aboutit pas : la main laissée au client
   =========================================================
   LE DÉFAUT (signalé le 5 octobre). Après un paiement Mobile Money
   refusé, le reçu affichait en boucle « Validez la demande sur votre
   téléphone… Ne payez pas une seconde fois », et l'on ne pouvait plus
   en sortir. Trois causes :

     - FeexPay répondait FAILED, notre serveur le disait (« echoue »),
       mais l'application ne lisait pas la réponse : le sablier tournait
       une minute et demie, puis annonçait « vous n'avez rien à
       refaire » — et recommençait à chaque réouverture du reçu ;
     - l'application dessine ses écrans un par un, et le reçu ne rendait
       la main qu'à la fin de cette attente : retour, « Mes commandes »,
       l'accueil restaient sans effet pendant une minute et demie ;
     - après l'achat, revenir en arrière depuis le panier ramenait au
       formulaire de commande, qui renvoyait au panier : le bouton
       retour du téléphone tournait entre ces deux écrans.

   Ce que le banc prouve :

     1. UN REFUS DE FEEXPAY ARRÊTE L'ATTENTE sur-le-champ : plus de
        sablier, le message du serveur, « Réessayer le paiement » et
        « Fermer » — et plus aucune question posée à FeexPay ;
     2. « FERMER » RETIRE LE MESSAGE ;
     3. RÉESSAYER RELANCE LA MÊME COMMANDE, avec l'opérateur et le
        numéro choisis, puis attend de nouveau — et le reçu passe à
        « Commande confirmée ! » quand la base le dit ;
     4. « ARRÊTER L'ATTENTE » arrête de questionner FeexPay, dit ce qui
        se passera si le client a été débité, et « Vérifier à nouveau »
        reprend ;
     5. QUITTER LE REÇU N'ATTEND PAS : « Mes commandes » s'affiche tout
        de suite, et l'attente s'arrête ;
     6. SANS DEMANDE EN COURS, le reçu propose de régler la commande ;
     7. UNE COMMANDE NON ABOUTIE OU ANNULÉE n'a pas de sablier ;
     8. LE RETOUR ARRIÈRE NE TOURNE PLUS EN ROND après un achat.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-paiement-echoue.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-paiement-echoue.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const REFUS = "Le versement n'a pas abouti. Vérifiez votre solde, puis réessayez — rien n'a été débité.";
const COMMANDE = (etat = "a_payer") => ({ id: "cmd_x", numero: "BZ-000042", total: 300000, devise: "FCFA",
  etat, client: { nom: "Koffi", tel: "0197000000", indicatif: "229", adresse: "Cotonou" },
  boutiques: [{ id: "bou_a", nom: "Alpha", montant: 300000,
    lignes: [{ nom: "Ordinateur", prix: 300000, quantite: 1 }] }] });
const BOUTIQUE = { id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech", icone: "magasin",
  couleur: "#0047D9", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 };
const PRODUIT = { id: "prod_1", boutique_id: "bou_a", nom: "Ordinateur", code: "0001", prix: 300000,
  categorie_id: "cat_hightech", sous_categorie_id: "sc_x", stock: 5, disponible: true, images: [],
  cree_le: "2026-09-01T08:00:00Z", modifie_le: "2026-09-01T08:00:00Z" };

/**
 * L'application, sa base et notre fonction « feexpay », simulées.
 * « serveur » se modifie en cours d'essai : ce que FeexPay répond à la
 * prochaine vérification, l'état que la base rend.
 */
async function ouvrir({ commandes = [COMMANDE()], panier = null, hash = "#/commande/cmd_x",
                        verdict = { etat: "a_payer", attente: true, statut: "PENDING" } } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 900 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    try {
      localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
      localStorage.setItem("bizzoo-commandes", JSON.stringify(a.commandes));
      if (a.panier) localStorage.setItem("bizzoo-panier", JSON.stringify(a.panier));
      localStorage.setItem("bizzoo-coordonnees", JSON.stringify({
        nom: "Koffi", tel: "0197000000", indicatif: "229", adresse: "Cotonou" }));
    } catch (_) { /* une page hors de l'application, au bout de l'historique */ }
  }, { commandes, panier });
  const serveur = { verdict, etat: { etat: "a_payer", remarque: "" }, appels: [] };
  await page.route("**/functions/v1/feexpay", (route) => {
    const corps = JSON.parse(route.request().postData() || "{}");
    serveur.appels.push(corps);
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (corps.action === "payer") {
      return d({ ouvert: true, reference: "ref_" + serveur.appels.length,
                 message: "Validez la demande sur votre téléphone." });
    }
    return d(serveur.verdict);
  });
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/suivre_commande")) return d(serveur.etat);
    if (c.startsWith("rpc/creer_commande")) return d({ ...COMMANDE(), boutiques: COMMANDE().boutiques });
    if (c.startsWith("rpc/")) return d([]);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: true, fournisseur: "feexpay",
      cle_publique: "", bac_a_sable: false }]);
    if (c.startsWith("produits")) return d([PRODUIT]);
    if (c.startsWith("boutiques")) return d([BOUTIQUE]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/client/index.html" + hash, { waitUntil: "domcontentloaded" });
  return { page, ctx, erreurs, serveur };
}

const verifications = (serveur) => serveur.appels.filter((a) => a.action === "verifier").length;
const carte = (page) => page.evaluate(() => {
  const a = document.querySelector("#re-attente");
  return a ? {
    etat: a.dataset.etat,
    sablier: !!a.querySelector(".chargement-rond"),
    texte: a.textContent.replace(/\s+/g, " ").trim(),
    boutons: [...a.querySelectorAll("button[data-attente]")].map((b) => b.textContent.trim()),
    formulaire: !!a.querySelector("#co-operateurs") && !!a.querySelector("#co-mm-tel"),
  } : null;
});
const attendreCarte = (page, etat, delai = 6000) => page.waitForFunction(
  (e) => (document.querySelector("#re-attente") || {}).dataset?.etat === e, etat, { timeout: delai })
  .then(() => true, () => false);

/* ------------------------------------------------------------------ */
titre("1. Un refus de FeexPay arrête l'attente sur-le-champ");
let refuse;
{
  refuse = await ouvrir({ verdict: { etat: "a_payer", echoue: true, erreur: REFUS } });
  const { page, serveur } = refuse;
  const t0 = Date.now();
  const vu = await attendreCarte(page, "echec", 6000);
  const delai = Date.now() - t0;
  const c = await carte(page);
  ok(vu && delai < 4000, "le refus s'affiche en " + delai + " ms, sans attendre la fin du sablier");
  ok(c && !c.sablier, "plus de sablier");
  ok(c && c.texte.startsWith(REFUS), "le message du serveur, tel quel (« " + (c ? c.texte.slice(0, 40) : "—") + "… »)");
  ok(c && !/Ne payez pas une seconde fois|Validez la demande/.test(c.texte),
    "plus de « Validez la demande… Ne payez pas une seconde fois » pour un versement refusé");
  ok(c && c.boutons.join("|") === "Réessayer le paiement|Fermer", "« Réessayer le paiement » et « Fermer » (" + (c ? c.boutons.join(", ") : "—") + ")");
  ok(c && c.formulaire, "l'opérateur et le numéro qui paie sont proposés");
  const n = verifications(serveur);
  await page.waitForTimeout(7000);
  ok(n === 1 && verifications(serveur) === 1, "une seule question à FeexPay, et plus rien ensuite (" + verifications(serveur) + ")");
}

titre("2. « Fermer » retire le message");
{
  const { page, ctx, erreurs } = refuse;
  await page.click('#re-attente [data-attente="fermer"]');
  ok(!(await carte(page)), "le message est parti");
  ok(await page.$(".re-entete") !== null, "le reçu, lui, reste à l'écran");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("3. Réessayer relance la même commande, puis attend de nouveau");
{
  const { page, ctx, erreurs, serveur } = await ouvrir({ verdict: { etat: "a_payer", echoue: true, erreur: REFUS } });
  await attendreCarte(page, "echec");
  const actif = await page.evaluate(() =>
    (document.querySelector("#re-attente .pay-methode.active") || {}).dataset?.reseau || "");
  ok(actif === "MTN", "l'opérateur du numéro de la commande est déjà choisi (" + actif + ")");
  await page.click('#re-attente [data-reseau="MOOV"]');
  await page.fill("#re-attente #co-mm-tel", "0194000000");
  serveur.verdict = { etat: "a_payer", attente: true, statut: "PENDING" };
  await page.click('#re-attente [data-attente="payer"]');
  await page.waitForTimeout(1500);
  const payer = serveur.appels.filter((a) => a.action === "payer");
  ok(payer.length === 1 && payer[0].commande === "cmd_x" && payer[0].reseau === "MOOV" &&
     payer[0].numero === "0194000000" && payer[0].tel === "0197000000",
    "une seule demande, pour la même commande, avec l'opérateur et le numéro choisis");
  const c = await carte(page);
  ok(c && c.etat === "attente" && c.sablier && c.boutons.join() === "Arrêter l'attente",
    "le reçu attend de nouveau, avec « Arrêter l'attente »");
  serveur.etat = { etat: "payee", remarque: "" };
  serveur.verdict = { etat: "payee", deja: true };
  const confirme = await page.waitForFunction(() => /Commande confirmée/.test(document.body.textContent),
    null, { timeout: 9000 }).then(() => true, () => false);
  ok(confirme && !(await carte(page)), "la base dit « payée » : « Commande confirmée ! », et plus de carte d'attente");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("4. « Arrêter l'attente », puis « Vérifier à nouveau »");
{
  const { page, ctx, erreurs, serveur } = await ouvrir();
  await attendreCarte(page, "attente");
  await page.waitForTimeout(1200);
  await page.click('#re-attente [data-attente="arreter"]');
  const c = await carte(page);
  ok(c && c.etat === "arretee" && !c.sablier, "le sablier s'arrête");
  ok(c && /Vous avez arrêté l'attente/.test(c.texte) && /vous n'avez rien à refaire/.test(c.texte) &&
     /BZ-000042/.test(c.texte),
    "il dit ce qui se passera si le client a été débité, et le numéro à garder");
  ok(c && c.boutons.join("|") === "Vérifier à nouveau|Fermer", "« Vérifier à nouveau » et « Fermer »");
  const n = verifications(serveur);
  await page.waitForTimeout(6500);
  ok(verifications(serveur) - n <= 1, "on ne questionne plus FeexPay (au plus la question déjà partie)");
  const avant = verifications(serveur);
  await page.click('#re-attente [data-attente="verifier"]');
  await page.waitForTimeout(1500);
  const r = await carte(page);
  ok(r && r.etat === "attente" && verifications(serveur) > avant, "« Vérifier à nouveau » reprend l'attente");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("5. Quitter le reçu n'attend pas");
{
  const { page, ctx, erreurs, serveur } = await ouvrir();
  await attendreCarte(page, "attente");
  /* Juste après une question à FeexPay : c'est là que l'attente dort le
     plus longtemps avant la suivante. Un reçu qui attendrait la fin de
     sa boucle avant de rendre la main se verrait ici. */
  for (let i = 0; i < 50 && verifications(serveur) < 1; i++) await page.waitForTimeout(100);
  await page.waitForTimeout(200);
  const t0 = Date.now();
  await page.evaluate(() => { location.hash = "#/mes-commandes"; });
  const parti = await page.waitForFunction(() => !document.querySelector("#re-attente") &&
    /^#\/mes-commandes/.test(location.hash), null, { timeout: 15000 }).then(() => true, () => false);
  const delai = Date.now() - t0;
  ok(parti && delai < 1000, "« Mes commandes » s'affiche en " + delai + " ms — il fallait attendre la fin du sablier");
  const n = verifications(serveur);
  await page.waitForTimeout(7000);
  ok(verifications(serveur) - n <= 1, "l'attente s'arrête avec l'écran (" + (verifications(serveur) - n) + " question après)");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("6. Aucune demande en cours : le reçu propose de régler");
{
  const { page, ctx, erreurs } = await ouvrir({ verdict: { etat: "a_payer", attente: true, raison: "aucun paiement ouvert" } });
  const vu = await attendreCarte(page, "rien");
  const c = await carte(page);
  ok(vu && c && !c.sablier && /Aucune demande de paiement n'est en cours/.test(c.texte),
    "« Aucune demande de paiement n'est en cours pour cette commande »");
  ok(c && c.boutons.join("|") === "Payer maintenant|Fermer" && c.formulaire, "« Payer maintenant », avec l'opérateur et le numéro");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("7. Commande non aboutie ou annulée : pas de sablier");
for (const etat of ["echouee", "annulee"]) {
  const { page, ctx, erreurs, serveur } = await ouvrir({ commandes: [COMMANDE(etat)] });
  await page.waitForTimeout(3500);
  ok(!(await carte(page)), etat + " : aucune carte d'attente");
  ok(verifications(serveur) === 0, etat + " : rien n'est demandé à FeexPay");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("8. Après un achat, le retour arrière ne tourne plus en rond");
{
  const { page, ctx, erreurs } = await ouvrir({ commandes: [], panier: [{ produitId: "prod_1", quantite: 1 }], hash: "#/" });
  await page.waitForTimeout(1500);
  for (const h of ["#/panier", "#/commande"]) {
    await page.evaluate((x) => { location.hash = x; }, h);
    await page.waitForTimeout(1200);
  }
  await page.click("#co-payer");
  const recu = await page.waitForFunction(() => location.hash === "#/commande/cmd_x", null, { timeout: 8000 })
    .then(() => true, () => false);
  ok(recu, "le paiement part, le reçu s'ouvre");
  const vus = [];
  for (let i = 0; i < 2; i++) {
    await page.evaluate(() => history.back());
    await page.waitForTimeout(1200);
    vus.push(await page.evaluate(() => location.hash).catch(() => "(hors de l'application)"));
  }
  ok(vus[0] === "#/panier", "retour : le panier (" + vus[0] + ")");
  ok(vus[1] === "#/", "retour encore : on en sort, vers l'accueil (" + vus[1] + ") — avant, le panier revenait sans fin");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("8 bis. Un formulaire de commande au panier vide ne piège pas le retour");
{
  /* Un lien vers « #/commande » quand le panier est vide : le formulaire
     renvoie au panier. S'il EMPILAIT ce renvoi, revenir en arrière depuis
     le panier ramènerait au formulaire, qui renverrait au panier… */
  const { page, ctx, erreurs } = await ouvrir({ commandes: [], hash: "#/" });
  await page.waitForTimeout(1500);
  await page.evaluate(() => { location.hash = "#/commande"; });
  await page.waitForTimeout(1300);
  ok(await page.evaluate(() => location.hash) === "#/panier", "le formulaire au panier vide renvoie au panier");
  await page.evaluate(() => history.back());
  await page.waitForTimeout(1300);
  const ou = await page.evaluate(() => location.hash).catch(() => "(hors de l'application)");
  ok(ou === "#/", "retour : l'accueil, d'où l'on venait (" + ou + ")");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n\x1b[31m" + echecs + " échec(s)\x1b[0m" : "\n\x1b[32mLe paiement qui n'aboutit pas laisse la main au client ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
