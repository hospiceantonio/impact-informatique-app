/* =========================================================
   La barre de suivi, et le bouton « J'ai bien reçu »
   =========================================================
   CE QU'ON DÉFEND ICI. La liste des commandes ne disait que le
   paiement : une commande payée restait « Payée » jusqu'au bout,
   même partie, même livrée. Elle porte maintenant une barre à
   quatre paliers — Payé, Préparé, En route, Livré — et, au
   dernier, le bouton par lequel le client accuse réception.

   TROIS RÈGLES Y SONT ÉPROUVÉES, parce que ce sont elles qui
   peuvent se défaire sans qu'on le voie :

   1. LE PALIER LE MOINS AVANCÉ. Une commande traverse parfois
      deux boutiques. Si l'une roule et l'autre prépare, le
      client doit lire « Préparé » : annoncer l'étape la plus
      avancée mentirait sur ce qu'il attend encore.

   2. LE BOUTON NE PARAÎT QU'À « LIVRÉ », et disparaît une fois
      la réception confirmée. Un bouton offert trop tôt ferait
      confirmer un colis qu'on n'a pas.

   3. LA CARTE EST UN LIEN. Le bouton vit dedans : sans
      « preventDefault », le doigt ouvrirait la commande au lieu
      de confirmer. Le constat porte donc sur l'adresse de la
      page APRÈS le clic, pas seulement sur ce qui est parti.

   ON REGARDE CE QUI QUITTE L'APPLICATION — les appels à la base,
   leur nombre et leurs arguments — et non ce que l'écran affiche :
   l'écran se repeint avant la réponse, et se repeindrait de la
   même façon si rien n'était parti.
   ========================================================= */
/* Playwright n'est pas une dépendance du projet : le chemin se donne
   par PLAYWRIGHT, le navigateur par CHROMIUM, l'adresse par BANC_URL. */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-suivi.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const MOI = "cc111111-1111-1111-1111-111111111111";
const BOU = [
  { id:"bou_a", nom:"IMPACT", secteur:"Informatique", categorie_id:null,
    icone:"portable", couleur:"#0B5CF5", devise:"FCFA", indicatif:"229", actif:true, ordre:1 },
  { id:"bou_b", nom:"MODE COTONOU", secteur:"Mode", categorie_id:null,
    icone:"tshirt", couleur:"#6C3FBF", devise:"FCFA", indicatif:"229", actif:true, ordre:2 },
];
const L = (id, bou, etat, confirme) => ({ id, boutique_id:bou, produit_id:"p1",
  nom:"Article", code:"0001", reference:"", prix:1650, quantite:1, etat,
  confirme_le: confirme ? "2026-09-12T10:00:00Z" : null });

/* Chaque commande éprouve un palier. La dernière en éprouve la RÈGLE :
   deux boutiques, l'une qui roule, l'autre qui prépare — le client doit
   lire « Préparé », l'étape la moins avancée. */
let deuxRemises = false;
function commandes() {
  return [
    { id:"c1", numero:"BZ-001", total:1650, devise:"FCFA", etat:"payee",
      cree_le:"2026-09-12T09:00:00Z", commande_lignes:[L("l1","bou_a","vue")] },
    { id:"c2", numero:"BZ-002", total:1650, devise:"FCFA", etat:"payee",
      cree_le:"2026-09-12T09:01:00Z", commande_lignes:[L("l2","bou_a","preparee")] },
    { id:"c3", numero:"BZ-003", total:1650, devise:"FCFA", etat:"payee",
      cree_le:"2026-09-12T09:02:00Z", commande_lignes:[L("l3","bou_a","en_livraison")] },
    { id:"c4", numero:"BZ-004", total:1650, devise:"FCFA", etat:"payee",
      cree_le:"2026-09-12T09:03:00Z", commande_lignes:[L("l4","bou_a","remise")] },
    { id:"c5", numero:"BZ-005", total:1650, devise:"FCFA", etat:"payee",
      cree_le:"2026-09-12T09:04:00Z", commande_lignes:[L("l5","bou_a","remise",true)] },
    { id:"c6", numero:"BZ-006", total:3300, devise:"FCFA", etat:"payee",
      cree_le:"2026-09-12T09:05:00Z",
      commande_lignes: deuxRemises
        ? [L("l6","bou_a","remise"), L("l7","bou_b","remise")]
        : [L("l6","bou_a","en_livraison"), L("l7","bou_b","preparee")] },
    { id:"c7", numero:"BZ-007", total:1650, devise:"FCFA", etat:"a_payer",
      cree_le:"2026-09-12T09:06:00Z", commande_lignes:[L("l8","bou_a","nouvelle")] },
  ];
}

const ctx = await nav.newContext({ viewport:{ width:390, height:1900 } });
const page = await ctx.newPage();
page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));
await page.addInitScript((moi) => {
  localStorage.setItem("impact-config", JSON.stringify({ url:"https://base-absente.invalid", cle:"k" }));
  localStorage.removeItem("impact-boutique");
  const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
    .replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
  localStorage.setItem("bizzoo-session", JSON.stringify({
    access_token: b64({alg:"HS256"})+"."+b64({sub:moi})+".s",
    refresh_token:"r", expire_a: Date.now()+3600000, email:"moi@essai.bj" }));
}, MOI);
const appels = [];
let confirmees = new Set();
await page.route("**/rest/v1/**", (r) => {
  const req = r.request();
  const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//,"");
  if (req.method() !== "GET") {
    let corps = null;
    try { corps = req.postDataJSON(); } catch (_) { /* pas du JSON */ }
    appels.push({ chemin:c, corps });
    /* La base répond comme la vraie : la confirmation est ENREGISTRÉE,
       et la relecture qui suit doit la voir. Une doublure qui oublierait
       laisserait l'essai croire que rien n'a changé. */
    if (c === "rpc/confirmer_reception" && corps) {
      confirmees.add(corps.commande + "|" + corps.boutique);
      return r.fulfill({status:200,contentType:"application/json",body:"true"});
    }
  }
  const d = (x) => r.fulfill({status:200,contentType:"application/json",body:JSON.stringify(x)});
  if (c === "rpc/produits_populaires") return d([]);
  if (c.startsWith("commandes")) {
    const l = commandes();
    for (const cm of l) {
      for (const li of cm.commande_lignes) {
        if (confirmees.has(cm.id + "|" + li.boutique_id)) {
          li.confirme_le = "2026-09-12T11:00:00Z";
        }
      }
    }
    return d(l);
  }
  if (c.startsWith("clients")) return d([{ id:MOI, nom:"MOI", tel:"97000001",
    indicatif:"229", tel_verifie:true, type_compte:"client", revendeur_etat:"aucune" }]);
  if (c.startsWith("categories")) return d([]);
  if (c.startsWith("boutiques")) return d(BOU);
  if (c.startsWith("produits")) return d([]);
  if (c.startsWith("boutique")) return d([{id:1,nom:"BIZZOO",devise:"FCFA",indicatif:"229"}]);
  return d([]);
});
await page.goto(BASE + "/client/index.html", { waitUntil:"domcontentloaded" });
await page.waitForTimeout(1700);
await page.evaluate(() => { location.hash = "#/mes-commandes"; });
await page.waitForTimeout(1900);
await page.screenshot({ path:"/tmp/claude-0/suivi.png", fullPage:true });

const cartes = await page.evaluate(() =>
  [...document.querySelectorAll(".re-resume")].map((a) => {
    const barre = a.querySelector(".re-barre");
    const pas = [...a.querySelectorAll(".re-barre-pas")];
    return {
      numero: (a.querySelector(".re-resume-numero")||{}).textContent.trim(),
      badge: (a.querySelector(".badge:not(.badge-local)")||{}).textContent || "",
      barre: !!barre,
      pas: pas.length,
      remplis: pas.filter((p) => p.classList.contains("fait")).length,
      ici: pas.findIndex((p) => p.classList.contains("ici")) + 1,
      dit: barre ? barre.getAttribute("aria-label") : "",
      mots: [...a.querySelectorAll(".re-barre-mots span")].map((s) => s.textContent),
    };
  }));

const par = (n) => cartes.find((c) => c.numero.startsWith(n)) || {};

titre("Chaque palier remplit la barre d'un cran de plus");
for (const [n, badge, cran] of [
  ["BZ-001", "Payé", 1], ["BZ-002", "Colis préparé", 2],
  ["BZ-003", "Livraison en cours", 3], ["BZ-004", "Livré", 4]]) {
  const c = par(n);
  ok(c.badge === badge, n + " porte « " + badge + " » (" + c.badge + ")");
  ok(c.remplis === cran, "et " + cran + " segment(s) rempli(s) (" + c.remplis + ")");
  ok(c.ici === cran, "l'étape en cours est la " + cran + "e (" + c.ici + ")");
}

titre("La barre a quatre paliers, et ils sont nommés");
{
  const c = par("BZ-002");
  ok(c.pas === 4, "quatre segments (" + c.pas + ")");
  ok(c.mots.join(" · ") === "Payé · Préparé · En route · Livré",
    "et quatre mots sous eux (" + c.mots.join(" · ") + ")");
}

titre("DEUX BOUTIQUES : c'est la MOINS avancée qui parle");
{
  /* L'une roule, l'autre prépare. Annoncer « en livraison » ferait
     attendre le client chez lui pour un colis qui n'est pas parti. */
  const c = par("BZ-006");
  ok(c.badge === "Colis préparé",
    "la commande à deux boutiques affiche « Colis préparé » (" + c.badge + ")");
  ok(c.remplis === 2, "et s'arrête au deuxième cran (" + c.remplis + ")");
}

titre("Le client a confirmé : la barre est pleine, la pastille le dit");
{
  const c = par("BZ-005");
  ok(c.badge === "Reçu confirmé", "« Reçu confirmé » (" + c.badge + ")");
  ok(c.remplis === 4, "barre pleine (" + c.remplis + ")");
}

titre("Pas encore payée : aucune barre, et c'est voulu");
{
  const c = par("BZ-007");
  ok(!c.barre, "aucune barre sous une commande impayée");
  ok(/attente/i.test(c.badge), "c'est le paiement qui parle (" + c.badge + ")");
}

titre("Elle parle aussi à qui ne la voit pas");
{
  const c = par("BZ-003");
  ok(/Livraison en cours/.test(c.dit) && /3 sur 4/.test(c.dit),
    "la barre s'annonce (" + c.dit + ")");
}

titre("À « Livré », le client peut confirmer — sans ouvrir la commande");
{
  const avant = page.url();
  const avaitBouton = await page.evaluate(() =>
    !!document.querySelector('[data-recu="c4"]'));
  ok(avaitBouton, "la commande livrée porte un bouton « J'ai bien reçu »");

  const ailleurs = await page.evaluate(() => ({
    payee: !!document.querySelector('[data-recu="c1"]'),
    route: !!document.querySelector('[data-recu="c3"]'),
    deja:  !!document.querySelector('[data-recu="c5"]'),
    impayee: !!document.querySelector('[data-recu="c7"]'),
  }));
  ok(!ailleurs.payee && !ailleurs.route,
    "et aucune de celles qui ne sont pas encore livrées");
  ok(!ailleurs.deja, "ni celle que le client a déjà confirmée");
  ok(!ailleurs.impayee, "ni une commande impayée");

  await page.click('[data-recu="c4"]');
  await page.waitForTimeout(1400);

  /* LA FAUTE QU'UN BANC DE CHAMPS NE VERRAIT PAS : la carte est un
     lien, le bouton vit dedans. Sans « preventDefault », le toucher
     ouvre la commande et la confirmation se perd. */
  ok(page.url() === avant,
    "la commande ne s'est PAS ouverte sous le doigt");

  const rpc = appels.filter((a) => a.chemin === "rpc/confirmer_reception");
  ok(rpc.length === 1, "une confirmation part vers la base (" + rpc.length + ")");
  ok(rpc[0] && rpc[0].corps && rpc[0].corps.commande === "c4",
    "pour la bonne commande");
  ok(rpc[0] && rpc[0].corps && rpc[0].corps.boutique === "bou_a",
    "et la bonne boutique");

  const apres = await page.evaluate(() => {
    const a = [...document.querySelectorAll(".re-resume")]
      .find((x) => /BZ-004/.test(x.textContent));
    return a ? {
      badge: (a.querySelector(".badge")||{}).textContent || "",
      bouton: !!a.querySelector("[data-recu]"),
    } : null;
  });
  ok(apres && apres.badge === "Reçu confirmé",
    "la pastille passe à « Reçu confirmé » (" + (apres ? apres.badge : "") + ")");
  ok(apres && !apres.bouton, "et le bouton disparaît");
}

titre("Deux boutiques livrées : une seule confirmation pour les deux");
{
  /* BZ-006 a ses deux boutiques en « remise » dans ce second décor :
     le client dit « j'ai tout reçu » d'un seul geste, et la base est
     signée pour CHACUNE — elle signe par boutique. */
  await page.evaluate(() => { location.hash = "#/"; });
  await page.waitForTimeout(600);
  appels.length = 0;
  deuxRemises = true;
  await page.evaluate(() => { location.hash = "#/mes-commandes"; });
  await page.waitForTimeout(1700);

  const b = await page.evaluate(() => {
    const el = document.querySelector('[data-recu="c6"]');
    return el ? el.textContent.replace(/\s+/g, " ").trim() : "";
  });
  ok(/2 boutiques/.test(b), "le bouton annonce les deux boutiques (" + b + ")");

  await page.click('[data-recu="c6"]');
  await page.waitForTimeout(1600);
  const rpc = appels.filter((a) => a.chemin === "rpc/confirmer_reception");
  ok(rpc.length === 2, "deux confirmations partent (" + rpc.length + ")");
  const vises = rpc.map((r) => r.corps.boutique).sort().join(",");
  ok(vises === "bou_a,bou_b", "une par boutique (" + vises + ")");
}

titre("Rien ne déborde");
{
  const deborde = await page.evaluate(() =>
    document.documentElement.scrollWidth > document.documentElement.clientWidth + 1);
  ok(!deborde, "la liste tient dans la largeur");
  const coupe = await page.evaluate(() =>
    [...document.querySelectorAll(".re-barre-mots span")]
      .filter((s) => s.scrollWidth > s.clientWidth + 1).length);
  ok(coupe === 0, "et aucun mot n'est coupé (" + coupe + ")");
}

await ctx.close();
await nav.close();
console.log("\n" + (echecs ? "  " + echecs + " ÉCHEC(S)" : "  Tout passe."));
process.exit(echecs ? 1 : 0);
