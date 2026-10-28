/* =========================================================
   Banc — « Le paiement en ligne n'est pas encore ouvert » à tort (3.70.0)

   Un client a vu ce message, et le bouton « Envoyer sur WhatsApp », alors
   que le paiement en ligne était ouvert. L'application lisait le réglage
   UNE fois, à l'ouverture : une lecture ratée (réseau faible) ou faite
   pendant une coupure le croyait fermé, et l'écran de commande ne le
   revérifiait plus jamais — la commande partait sur WhatsApp, sans payer.

     1. fermé à l'ouverture, rouvert depuis : l'écran de commande relit,
        et passe au paiement ;
     2. lecture ratée à l'ouverture : « Envoyer sur WhatsApp » revérifie
        d'abord, et propose de payer si c'est ouvert ;
     3. sans réseau, le dernier réglage connu (ouverture précédente) tient ;
     4. vraiment fermé : WhatsApp, comme avant.

     PLAYWRIGHT=… CHROMIUM=… BANC_URL=http://127.0.0.1:5191 node tools/banc-paiement-ferme.mjs
   ========================================================= */
const { chromium } = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default;
const BASE = process.env.BANC_URL || "http://127.0.0.1:5191";
const EXE = process.env.CHROMIUM || undefined;
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE, args: ["--no-sandbox"] } : { args: ["--no-sandbox"] });

const BOUTIQUES = [{ id: "bou_a", nom: "Alpha", devise: "FCFA", indicatif: "229", whatsapp: "22997000001", actif: true, ordre: 1 }];
const PRODUIT = { id: "prod_1", boutique_id: "bou_a", nom: "Casque", code: "0001", prix: 2000, stock: 5, disponible: true,
  images: [], cree_le: "2026-10-01T08:00:00Z", modifie_le: "2026-10-02T08:00:00Z" };
const CLIENT = { nom: "Lawani", tel: "0147453651", indicatif: "229", adresse: "Agla" };

/** etats : ce que la base répond à chaque lecture du réglage — "ouvert", "ferme" ou "panne". */
async function ouvrir({ etats, cache = null }) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1200 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.setItem("bizzoo-panier", JSON.stringify([{ produitId: "prod_1", quantite: 1 }]));
    localStorage.setItem("bizzoo-coordonnees", JSON.stringify(a.client));
    if (a.cache) localStorage.setItem("bizzoo-paiement-reglages", JSON.stringify(a.cache));
  }, { client: CLIENT, cache });
  const serveur = { lectures: 0, etats: [...etats] };
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, statut = 200) => route.fulfill({ status: statut, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("paiement")) {
      serveur.lectures++;
      const e = serveur.etats.length > 1 ? serveur.etats.shift() : serveur.etats[0];
      if (e === "panne") return d({ message: "indisponible" }, 503);
      return d([{ id: 1, actif: e === "ouvert", fournisseur: "feexpay", cle_publique: "", bac_a_sable: false,
        taux_acompte: 100, frais_livraison: 1000 }]);
    }
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    if (c.startsWith("produits")) return d([PRODUIT]);
    if (c.startsWith("boutiques")) return d(BOUTIQUES);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("rpc/")) return d(null);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/client/index.html#/", { waitUntil: "domcontentloaded" });
  await pause(1500);
  return { page, ctx, erreurs, serveur };
}
const aller = async (page, h) => { await page.evaluate((x) => { location.hash = x; }, h); await pause(1500); };
const bouton = (page) => page.evaluate(() => (document.querySelector("#co-payer") ? "payer"
  : document.querySelector("#co-whatsapp") ? "whatsapp" : "aucun"));

titre("1. Fermé à l'ouverture, rouvert depuis : l'écran de commande relit");
{
  const { page, ctx, erreurs } = await ouvrir({ etats: ["ferme", "ouvert"] });
  await aller(page, "#/commande");
  await pause(800);
  ok(await bouton(page) === "payer", "l'écran passe au paiement (« Payer »), plus de WhatsApp");
  ok(!/pas encore ouvert/.test(await page.evaluate(() => document.body.innerText)), "le message « pas encore ouvert » a disparu");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("2. Lecture ratée à l'ouverture : WhatsApp revérifie d'abord");
{
  const { page, ctx, erreurs, serveur } = await ouvrir({ etats: ["panne", "panne", "ouvert"] });
  await aller(page, "#/commande");
  ok(await bouton(page) === "whatsapp", "sans réglage lisible : « Envoyer sur WhatsApp » (rien de mieux à proposer)");
  serveur.etats = ["ouvert"];
  await page.click("#co-whatsapp");
  await pause(1200);
  ok(await bouton(page) === "payer", "le client touche WhatsApp : c'est ouvert, l'écran passe au paiement");
  ok(!(await page.$("#co-liens .btn-wa, #co-liens a")), "et aucun lien WhatsApp n'est proposé");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("3. Sans réseau, le dernier réglage connu tient");
{
  const cache = { actif: true, fournisseur: "feexpay", clePublique: "", bacASable: false, tauxAcompte: 100, fraisLivraison: 1000, livraison: null };
  const { page, ctx, erreurs } = await ouvrir({ etats: ["panne"], cache });
  await aller(page, "#/commande");
  ok(await bouton(page) === "payer", "réseau en panne, mais ouvert à la dernière lecture : « Payer »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("4. Vraiment fermé : WhatsApp, comme avant");
{
  const { page, ctx } = await ouvrir({ etats: ["ferme"] });
  await aller(page, "#/commande");
  ok(await bouton(page) === "whatsapp", "« Envoyer sur WhatsApp »");
  await page.click("#co-whatsapp");
  await pause(1200);
  ok(await page.evaluate(() => /Envoyez votre commande/.test(document.body.innerText)), "et les liens WhatsApp s'affichent");
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " échec(s)" : "\nTout passe.");
process.exit(echecs ? 1 : 0);
