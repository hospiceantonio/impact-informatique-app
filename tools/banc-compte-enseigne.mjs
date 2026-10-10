/* =========================================================
   Le compte de BIZZOO entre dans l'application admin
   =========================================================
   CE QUE CE BANC ÉPROUVE, ET POURQUOI IL EXISTE. Les comptes de
   BIZZOO — administrateur ou modérateur rattaché à AUCUNE
   boutique — étaient prêts en base : « peut_agir_sur() » leur
   répond oui partout, leurs interrupteurs posent les limites.
   Mais l'application admin ne les laissait pas entrer. Au
   démarrage, « boutiqueDeDepart() » ne donnait une boutique qu'au
   superadministrateur, et la porte « Boutique à confier » arrêtait
   tout compte sans boutique ouverte. Sur la vraie base, le gérant
   passait un compte en « administrateur de BIZZOO »… et ce compte
   ne pouvait plus rien ouvrir. Le banc de la base était vert : il
   éprouvait la base, pas la porte.

   Les constats portent donc sur L'APPLICATION ELLE-MÊME, ouverte
   avec chacun des comptes :
     1. l'administrateur de BIZZOO entre, sur une boutique ;
     2. il passe d'une boutique à l'autre ;
     3. ses interrupteurs décident de ce qu'il voit ;
     4. « Les boutiques » lui ouvre les réglages de la boutique ;
     5. sans « Les commandes », les commandes lui sont fermées ;
     6. le modérateur de BIZZOO entre aussi ;
     7. le livreur de BIZZOO va droit à ses courses ;
     8. un compte dont la boutique n'existe plus reste arrêté,
        avec un conseil qui ne mène plus à une impasse ;
     9. un compte de boutique reste dans la sienne ;
    10. le superadministrateur garde la gestion des boutiques.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-compte-enseigne.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const BOU = [
  { id: "bou_tech", nom: "IMPACT", secteur: "Informatique", categorie_id: "cat_h",
    icone: "portable", couleur: "#2550B7", devise: "FCFA", indicatif: "229",
    actif: true, ordre: 1 },
  { id: "bou_mode", nom: "CREATIS", secteur: "Mode", categorie_id: "cat_m",
    icone: "sac", couleur: "#E11", devise: "FCFA", indicatif: "229",
    actif: true, ordre: 2 },
];

/* Une fiche de compte, telle que la table « profils » la rend. Les
   interrupteurs ont les défauts du schéma : commandes et catalogue
   allumés, boutiques et chiffres éteints. */
const fiche = (id, role, boutique, reste) => ({
  id, email: id.slice(0, 4) + "@bizzoo.bj", nom: "", tel: "", role, actif: true,
  peut_modifier_produits: true, boutique_id: boutique,
  peut_commandes: true, peut_boutiques: false, peut_finances: false, ...(reste || {}),
});

const ADMIN_BIZZOO = "aaaa0000-0000-0000-0000-000000000001";
const MODO_BIZZOO = "bbbb0000-0000-0000-0000-000000000002";
const LIVREUR_BIZZOO = "cccc0000-0000-0000-0000-000000000003";
const ORPHELIN = "dddd0000-0000-0000-0000-000000000004";
const MODO_IMPACT = "eeee0000-0000-0000-0000-000000000005";
const SUPER = "ffff0000-0000-0000-0000-000000000006";

let lectures = [];

/**
 * Ouvre l'application admin au nom d'un compte. « profil » est SA
 * fiche : la base ne rend à un compte d'enseigne que la sienne
 * (« profils lecture »), la doublure fait de même.
 */
async function ouvrir(profil, avant) {
  lectures = [];
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1900 } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({
      url: "https://base-absente.invalid", cle: "cle-de-banc" }));
    if (a.memorisee) localStorage.setItem("impact-admin-boutique", a.memorisee);
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: a.moi }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
  }, { moi: profil.id, email: profil.email, memorisee: (avant || {}).memorisee || "" });

  await page.route("**/auth/v1/**", (route) => route.fulfill({
    status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    if (req.method() === "GET") lectures.push(c + u.search);
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json",
      body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) return d(c === "rpc/mes_livraisons" ? [] : null);
    if (req.method() !== "GET") return route.fulfill({ status: 204, body: "" });
    if (c.startsWith("profils")) return d([profil]);
    if (c.startsWith("notifications")) return d([]);
    if (c.startsWith("commandes")) return d([]);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("produits")) return d([]);
    if (c.startsWith("categories")) return d([]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA",
      indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(2400);
  return { page, ctx };
}

/** Ce que l'écran montre, en une lecture. */
const releve = (page) => page.evaluate(() => {
  /* PAS « offsetParent » : la barre du bas est en position fixe, et un
     élément fixe n'a jamais d'« offsetParent » — le constat aurait dit
     « absente » d'une barre bien visible. */
  const vis = (el) => !!el && getComputedStyle(el).display !== "none" &&
    el.getBoundingClientRect().height > 0;
  const carte = document.querySelector(".carte-boutique-active");
  return {
    hash: location.hash || "#/",
    titre: (document.querySelector("#topbar h1") || {}).textContent || "",
    texte: document.querySelector("#vue").innerText,
    toast: (document.querySelector("#toasts .toast") || {}).textContent || "",
    barre: vis(document.querySelector("#tabbar")),
    carte: carte ? carte.innerText : "",
    carteLien: carte ? carte.getAttribute("href") || "" : "",
    actions: [...document.querySelectorAll(".topbar-actions a.btn-ic")]
      .map((a) => a.getAttribute("href")),
    ongletReglages: vis(document.querySelector('#tabbar [data-tab="/reglages"]')),
    ongletCompte: vis(document.querySelector('#tabbar [data-tab="/compte"]')),
  };
});

/** Va sur un écran, et relève où l'on atterrit et ce qu'on nous dit. */
async function aller(page, ecran) {
  await page.evaluate((h) => { location.hash = h; }, ecran);
  await page.waitForTimeout(1300);
  return releve(page);
}

/* ------------------------------------------------------------------ */
titre("1. L'administrateur de BIZZOO entre, sur une boutique");
{
  const { page, ctx } = await ouvrir(fiche(ADMIN_BIZZOO, "administrateur", null));
  const r = await releve(page);
  /* LE CONSTAT DE LA PANNE. Avant, ce compte s'arrêtait ici, sur un
     écran sans barre du bas, sans rien à toucher. */
  ok(r.titre !== "Boutique à confier",
    "il n'est plus arrêté sur « Boutique à confier » (" + JSON.stringify(r.titre) + ")");
  ok(r.barre, "la barre du bas est là");
  ok(/IMPACT/.test(r.carte), "il travaille sur une boutique : la première, IMPACT");
  ok(r.carteLien === "#/boutiques" && /en changer/.test(r.carte),
    "et la carte de la boutique ouverte l'invite à en changer");
  const surImpact = lectures.some((l) => /^produits/.test(l) && /boutique_id=eq\.bou_tech/.test(l));
  ok(surImpact, "le catalogue demandé à la base est celui d'IMPACT");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("2. Il passe d'une boutique à l'autre");
{
  const { page, ctx } = await ouvrir(fiche(ADMIN_BIZZOO, "administrateur", null));
  const r = await aller(page, "#/boutiques");
  ok(r.hash === "#/boutiques", "l'écran des boutiques lui est ouvert (" + r.hash + ")");
  const m = await page.evaluate(() => ({
    vignettes: document.querySelectorAll("[data-ouvrir]").length,
    creer: !!document.querySelector("#bq-nouvelle"),
    crayons: document.querySelectorAll("[data-boutique]").length,
    ranger: document.querySelectorAll("[data-monter],[data-descendre]").length,
  }));
  ok(m.vignettes === 2, "les deux boutiques se choisissent (" + m.vignettes + ")");
  /* CE QUI RESTE AU SUPERADMINISTRATEUR. La base refuserait de créer,
     de ranger ou de supprimer : l'écran ne le propose pas. */
  ok(!m.creer && !m.crayons && !m.ranger,
    "ni créer, ni renommer, ni ranger une boutique (" + JSON.stringify(m) + ")");
  lectures = [];
  await page.click('[data-ouvrir="bou_mode"]');
  await page.waitForTimeout(1500);
  const apres = await releve(page);
  ok(apres.hash === "#/" && /CREATIS/.test(apres.carte),
    "un appui sur CREATIS : retour à l'accueil, sur CREATIS");
  ok(/CREATIS/.test(apres.toast), "et il le lui dit (" + JSON.stringify(apres.toast) + ")");
  ok(lectures.some((l) => /^produits/.test(l) && /boutique_id=eq\.bou_mode/.test(l)),
    "le catalogue demandé est désormais celui de CREATIS");
  const retenue = await page.evaluate(() => localStorage.getItem("impact-admin-boutique"));
  ok(retenue === "bou_mode", "et la boutique est retenue pour la prochaine ouverture");
  await ctx.close();

  /* ET ELLE L'EST VRAIMENT : rouverte, l'application repart sur CREATIS. */
  const deux = await ouvrir(fiche(ADMIN_BIZZOO, "administrateur", null), { memorisee: "bou_mode" });
  const r2 = await releve(deux.page);
  ok(/CREATIS/.test(r2.carte), "rouverte, l'application repart sur CREATIS");
  await deux.ctx.close();
}

/* ------------------------------------------------------------------ */
titre("3. Ses interrupteurs décident de ce qu'il voit");
{
  /* Les défauts : commandes et catalogue, ni boutiques ni chiffres. */
  const { page, ctx } = await ouvrir(fiche(ADMIN_BIZZOO, "administrateur", null));
  const r = await releve(page);
  ok(r.actions.includes("#/commandes"), "l'icône des commandes est là (interrupteur allumé)");
  ok(r.actions.includes("#/avis") && r.actions.includes("#/sav"),
    "les avis et les réclamations aussi : il répond pour toutes les boutiques");
  ok(!r.actions.includes("#/historique") && !r.actions.includes("#/comptes"),
    "ni historique ni comptes : la base ne lui en rend rien");
  ok(!r.actions.includes("#/reglages") && r.actions.includes("#/compte"),
    "sans « Les boutiques », pas de réglages — mais son compte");
  ok(!r.ongletReglages && r.ongletCompte,
    "et la barre du bas en fait autant : « Mon compte » au lieu de « Réglages »");
  ok(!/Ce que vend votre boutique|Ce que rapportent les boutiques/.test(r.texte),
    "aucune carte de chiffres : les deux fonctions de la base la lui refusent");

  const reg = await aller(page, "#/reglages");
  ok(reg.hash === "#/" && /Les boutiques/.test(reg.toast),
    "« Réglages » le renvoie, en nommant l'interrupteur (" + JSON.stringify(reg.toast) + ")");
  for (const ecran of ["#/statistiques", "#/historique", "#/comptes"]) {
    const x = await aller(page, ecran);
    ok(x.hash === "#/" && /comptes de BIZZOO/.test(x.toast),
      ecran + " : renvoyé, avec une raison (" + JSON.stringify(x.toast) + ")");
  }
  const moi = await aller(page, "#/compte");
  ok(/Administrateur de BIZZOO/.test(moi.texte) && /toutes les boutiques/.test(moi.texte),
    "« Mon compte » dit ce qu'il est : administrateur de BIZZOO, toutes les boutiques");
  ok(/commandes, catalogue/.test(moi.texte),
    "et ce que ses interrupteurs lui ouvrent : commandes, catalogue");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("4. « Les boutiques » lui ouvre les réglages de la boutique ouverte");
{
  const { page, ctx } = await ouvrir(fiche(ADMIN_BIZZOO, "administrateur", null,
    { peut_boutiques: true }));
  const r = await releve(page);
  ok(r.actions.includes("#/reglages") && r.ongletReglages,
    "l'icône et l'onglet « Réglages » paraissent");
  const reg = await aller(page, "#/reglages");
  ok(reg.hash === "#/reglages" && reg.titre === "Réglages",
    "l'écran s'ouvre (" + reg.hash + ", " + JSON.stringify(reg.titre) + ")");
  const m = await page.evaluate(() => ({
    sous: (document.querySelector("#topbar .sous") || {}).textContent || "",
    enseigne: !!document.querySelector("[data-cible]"),
  }));
  ok(/IMPACT/.test(m.sous), "sur la boutique ouverte, IMPACT (" + JSON.stringify(m.sous) + ")");
  /* LES COORDONNÉES DE L'ENSEIGNE RESTENT AU SUPERADMINISTRATEUR. */
  ok(!m.enseigne, "sans le choix « BIZZOO / boutique », qui reste au superadministrateur");
  const hist = await aller(page, "#/historique");
  ok(hist.hash === "#/", "l'historique reste fermé même avec l'interrupteur");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("5. Sans « Les commandes », les commandes lui sont fermées");
{
  const { page, ctx } = await ouvrir(fiche(ADMIN_BIZZOO, "administrateur", null,
    { peut_commandes: false }));
  const r = await releve(page);
  ok(!r.actions.includes("#/commandes"), "l'icône des commandes disparaît");
  const c = await aller(page, "#/commandes");
  ok(c.hash === "#/" && /Les commandes/.test(c.toast),
    "et l'écran le renvoie, en nommant l'interrupteur (" + JSON.stringify(c.toast) + ")");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("6. Le modérateur de BIZZOO entre aussi");
{
  const { page, ctx } = await ouvrir(fiche(MODO_BIZZOO, "moderateur", null));
  const r = await releve(page);
  ok(r.titre !== "Boutique à confier" && r.barre, "il entre, barre du bas comprise");
  ok(/IMPACT/.test(r.carte) && r.carteLien === "#/boutiques",
    "sur IMPACT, et il peut changer de boutique");
  const b = await aller(page, "#/boutiques");
  ok(b.hash === "#/boutiques", "l'écran des boutiques lui est ouvert");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("7. Le livreur de BIZZOO va droit à ses courses");
{
  const { page, ctx } = await ouvrir(fiche(LIVREUR_BIZZOO, "livreur", null));
  const r = await releve(page);
  /* LA MÊME PORTE L'ARRÊTAIT : aucune boutique, et il n'en ouvre pas.
     Son seul écran est celui de ses courses. */
  ok(r.titre !== "Boutique à confier",
    "il n'est plus arrêté sur « Boutique à confier » (" + JSON.stringify(r.titre) + ")");
  ok(r.hash === "#/livraisons", "il arrive sur ses courses (" + r.hash + ")");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("8. Un compte dont la boutique n'existe plus reste arrêté");
{
  const { page, ctx } = await ouvrir(fiche(ORPHELIN, "administrateur", "bou_disparue"));
  const r = await releve(page);
  ok(r.titre === "Boutique à confier", "la porte tient pour lui (" + JSON.stringify(r.titre) + ")");
  ok(!r.barre, "sans barre du bas");
  ok(/n'existe plus/.test(r.texte), "l'écran dit pourquoi : sa boutique n'existe plus");
  /* L'ANCIEN CONSEIL MENAIT À UNE IMPASSE : rejouer le fichier SQL ne
     promeut plus personne dès qu'un superadministrateur existe. */
  ok(!/fichier SQL/.test(r.texte), "le conseil « exécuter le dernier fichier SQL » a disparu");
  ok(/BIZZOO — toutes les boutiques/.test(r.texte),
    "et il nomme l'autre issue : en faire un compte de BIZZOO");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("9. Un compte de boutique reste dans la sienne");
{
  const { page, ctx } = await ouvrir(fiche(MODO_IMPACT, "moderateur", "bou_tech"),
    { memorisee: "bou_mode" });
  const r = await releve(page);
  ok(/IMPACT/.test(r.carte), "il travaille sur SA boutique, même si une autre était retenue");
  ok(r.carteLien === "", "la carte de sa boutique ne mène nulle part : il n'en change pas");
  const b = await aller(page, "#/boutiques");
  ok(b.hash === "#/" && /super administrateur/.test(b.toast),
    "l'écran des boutiques lui reste fermé (" + JSON.stringify(b.toast) + ")");
  const refus = await page.evaluate(() => {
    try { Store.choisirBoutique("bou_mode"); return "accepté"; } catch (e) { return e.message; }
  });
  ok(/IMPACT/.test(refus), "et le store refuse de l'en sortir (" + JSON.stringify(refus) + ")");
  ok(/Ce que vend votre boutique/.test(r.texte), "ses chiffres de boutique restent là");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("10. Le superadministrateur garde la gestion des boutiques");
{
  const { page, ctx } = await ouvrir(fiche(SUPER, "superadministrateur", null));
  const b = await aller(page, "#/boutiques");
  const m = await page.evaluate(() => ({
    creer: !!document.querySelector("#bq-nouvelle"),
    crayons: document.querySelectorAll("[data-boutique]").length,
    vignettes: document.querySelectorAll("[data-ouvrir]").length,
  }));
  ok(b.hash === "#/boutiques" && m.creer && m.crayons === 2 && m.vignettes === 2,
    "créer, renommer et choisir, tout est là (" + JSON.stringify(m) + ")");
  const r = await aller(page, "#/");
  ok(r.actions.includes("#/historique") && r.actions.includes("#/comptes"),
    "son accueil garde l'historique et les comptes");
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec.\n"
  : "\nLe compte de BIZZOO entre, choisit sa boutique, et ses interrupteurs tiennent ✔\n");
process.exit(echecs ? 1 : 0);
