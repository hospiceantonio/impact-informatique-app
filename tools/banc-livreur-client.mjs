/* =========================================================
   Le reçu montre qui livre, et comment le joindre
   =========================================================
   CE QU'ON DÉFEND ICI. Sous chaque boutique d'une commande payée,
   le reçu montre le livreur à qui la course est confiée : son nom,
   son numéro, un bouton pour l'appeler, un autre pour lui écrire
   sur WhatsApp. La base décide qui a le droit de le voir
   (supabase/tests/99v-livreur-client.sql) ; l'écran, lui, doit :

     1. demander à la base, avec le numéro de la commande ;
     2. poser le nom, le numéro, et deux liens qui composent le bon
        numéro, indicatif compris ;
     3. mettre chaque livreur sous SA boutique ;
     4. ne rien montrer quand la base ne rend rien, ou ne connaît
        pas encore la question — et ne pas casser le reçu ;
     5. ne rien demander pour une commande pas encore payée ;
     6. dire qu'un livreur sans numéro est joignable par la boutique.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-livreur-client.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const BOU = [
  { id: "bou_a", nom: "IMPACT", secteur: "Informatique", categorie_id: null, icone: "portable",
    couleur: "#0B5CF5", devise: "FCFA", indicatif: "229", actif: true, ordre: 1, whatsapp: "0197000000" },
  { id: "bou_b", nom: "MODE COTONOU", secteur: "Mode", categorie_id: null, icone: "tshirt",
    couleur: "#6C3FBF", devise: "FCFA", indicatif: "229", actif: true, ordre: 2, whatsapp: "0197000001" },
];
const commande = (etat) => ({
  id: "cmd_l", numero: "BZ-000777", total: 9000, devise: "FCFA", etat,
  client: { nom: "Awa", tel: "0196000001", indicatif: "229", adresse: "Akpakpa" },
  boutiques: [
    { id: "bou_a", nom: "IMPACT", montant: 5000, etat: "en_livraison",
      lignes: [{ nom: "Souris", produit_id: "p1", quantite: 1, prix: 5000 }] },
    { id: "bou_b", nom: "MODE COTONOU", montant: 4000, etat: "preparee",
      lignes: [{ nom: "Tee-shirt", produit_id: "p2", quantite: 1, prix: 4000 }] },
  ],
  gardeeLe: Date.now(),
});

async function ouvrir({ etat = "payee", reponse = [], statut = 200 } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1800 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  const appels = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((c) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
    localStorage.setItem("bizzoo-commandes", JSON.stringify([c]));
  }, commande(etat));
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json",
    body: JSON.stringify({ external: { email: true, phone: true } }) }));
  await page.route("**/functions/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json",
    body: JSON.stringify({ ok: true, statut: "en_attente" }) }));
  await page.route("**/realtime/**", (r) => r.abort());
  await page.route("**/rest/v1/**", (r) => {
    const req = r.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, s = 200) => r.fulfill({ status: s, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/livreurs_de_ma_commande") {
      let corps = null;
      try { corps = req.postDataJSON(); } catch (_) { /* rien */ }
      appels.push(corps);
      return statut === 200 ? d(reponse)
        : d({ message: "Could not find the function public.livreurs_de_ma_commande" }, statut);
    }
    if (c.startsWith("rpc/suivre_commande")) return d({ etat: "a_payer" });
    if (c.startsWith("rpc/")) return d([]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: true, fournisseur: "feexpay",
      cle_publique: "", bac_a_sable: false, taux_acompte: 100 }]);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html", { waitUntil: "domcontentloaded" });
  await pause(1500);
  await page.evaluate(() => { location.hash = "#/commande/cmd_l"; });
  await pause(1800);
  const cartes = await page.evaluate(() =>
    [...document.querySelectorAll("[data-livreur-pour]")].map((z) => ({
      pour: z.dataset.livreurPour,
      visible: !z.hidden,
      texte: z.innerText.replace(/\s+/g, " ").trim(),
      appel: (z.querySelector('a[href^="tel:"]') || {}).href || "",
      wa: (z.querySelector('a[href^="https://wa.me/"]') || {}).href || "",
    })));
  return { ctx, page, erreurs, appels, cartes };
}

titre("1 à 3. Le livreur de chaque boutique, et de quoi le joindre");
{
  const o = await ouvrir({ reponse: [
    { boutique_id: "bou_a", nom: "Sèna", telephone: "0196554433", indicatif: "229" },
  ] });
  ok(o.appels.length === 1 && o.appels[0].cible === "cmd_l" && o.appels[0].tel === "0196000001",
    "le reçu demande à la base, avec la commande et son numéro (" + JSON.stringify(o.appels) + ")");
  const a = o.cartes.find((c) => c.pour === "bou_a") || {};
  const b = o.cartes.find((c) => c.pour === "bou_b") || {};
  ok(a.visible && /Votre livreur/.test(a.texte) && /Sèna/.test(a.texte),
    "sous IMPACT : « Votre livreur — Sèna » (" + a.texte + ")");
  ok(/01 96 55 44 33|0196554433|96 55 44 33/.test(a.texte), "avec son numéro lisible");
  ok(a.appel === "tel:+2290196554433", "« Appeler » compose le bon numéro (" + a.appel + ")");
  ok(a.wa.startsWith("https://wa.me/2290196554433?text=") && /BZ-000777/.test(decodeURIComponent(a.wa)),
    "« WhatsApp » écrit au livreur, en citant la commande (" + a.wa.slice(0, 45) + "…)");
  ok(b.visible === false, "MODE COTONOU n'a pas encore de livreur : sa place reste vide");
  ok(!o.erreurs.length, "aucune erreur dans la page" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("4. Rien à montrer, ou une base qui ne connaît pas la question");
{
  const vide = await ouvrir({ reponse: [] });
  ok(vide.cartes.length === 2 && vide.cartes.every((c) => !c.visible),
    "la base ne rend rien : aucune carte de livreur");
  await vide.ctx.close();
  const ancienne = await ouvrir({ statut: 404 });
  ok(ancienne.cartes.every((c) => !c.visible) && !ancienne.erreurs.length,
    "fonction inconnue de la base : rien, et le reçu tient");
  const reste = await ancienne.page.evaluate(() => /IMPACT/.test(document.body.innerText));
  ok(reste, "le reste du reçu est bien là");
  await ancienne.ctx.close();
}

titre("5. Pas encore payée : on ne demande rien");
{
  const o = await ouvrir({ etat: "a_payer", reponse: [
    { boutique_id: "bou_a", nom: "Sèna", telephone: "0196554433", indicatif: "229" }] });
  ok(o.appels.length === 0 && !o.cartes.length, "aucune question à la base, aucune place de livreur");
  await o.ctx.close();
}

titre("6. Un livreur sans numéro");
{
  const o = await ouvrir({ reponse: [{ boutique_id: "bou_b", nom: "Koffi", telephone: "", indicatif: "229" }] });
  const b = o.cartes.find((c) => c.pour === "bou_b") || {};
  ok(b.visible && /Koffi/.test(b.texte) && !b.appel && !b.wa && /boutique peut vous mettre en relation/.test(b.texte),
    "son nom, pas de bouton, et la boutique comme relais (" + b.texte + ")");
  await o.ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mLe client sait qui le livre, et peut le joindre ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
