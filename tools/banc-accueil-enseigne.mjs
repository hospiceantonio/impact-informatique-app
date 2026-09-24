/* =========================================================
   L'accueil de l'enseigne : le slogan, les boutiques, le site
   =========================================================
   TROIS CHANGEMENTS Y SONT ÉPROUVÉS, et surtout les pièges que
   chacun a révélés :

   1. LE SLOGAN DE BIZZOO, SOUS LE LOGO. Il vient de
      « Catalogue.enseigne() », jamais de « boutique() » — cette
      dernière le vide EXPRÈS sur l'accueil de l'enseigne, où le
      slogan d'une boutique tromperait sur les autres. Et il ne
      paraît que lorsque le bandeau orange se tait : en
      mono-boutique celui-ci porte déjà le même texte.

   2. LES BOUTIQUES PAR QUATRE (par trois jusqu'à la 3.49.0). Une
      case de grille vaut « min-width:auto » par défaut : un nom
      d'un seul long mot élargit sa colonne et la page se met à
      défiler de côté. Le constat porte donc sur la LARGEUR DE LA
      PAGE à 320 px, pas seulement sur le nombre de cartes par
      rangée — compter les cartes aurait été vert pendant que la
      page débordait.

   3. LE SITE WEB. Ce qui n'est pas une adresse ne doit pas
      devenir un lien : « mon site » donnerait « https://mon site »,
      un lien mort posé chez tous les clients et qui aurait l'air
      d'un vrai. Et le nom de colonne compte : la base attend
      « site_web », pas « siteWeb ».

   CE QUE LE BANC REGARDE : les mesures réelles à l'écran et ce qui
   PART vers la base — corps de la requête compris. Pas ce qui
   s'affiche après coup : l'écran se repeint avant la réponse.
   ========================================================= */
/* Playwright n'est pas une dépendance du projet : le chemin se donne
   par PLAYWRIGHT, le navigateur par CHROMIUM, l'adresse par BANC_URL. */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-accueil-enseigne.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

/* SEPT BOUTIQUES, dont une au nom très long et une au nom d'un mot :
   c'est là que l'alignement d'une rangée se défait. */
const NOMS = [
  ["IMPACT INFORMATIQUE", "High-Tech & Électronique"],
  ["MODE", "Mode"],
  ["LA MAISON DU MEUBLE COTONOU", "Maison & Jardin"],
  ["BEAUTÉ", "Beauté & Soins"],
  ["SUPER MARCHÉ AYIMEVO", "Épicerie"],
  ["AUTO", "Auto & Moto"],
  ["PHARMACIE CENTRALE", "Santé"],
];
const BOU = NOMS.map(([nom, secteur], i) => ({
  id: "bou_" + i, nom, secteur, categorie_id: null, slogan: "Slogan de " + nom,
  icone: "magasin", couleur: "#0B5CF5", logo: "", devise: "FCFA",
  indicatif: "229", actif: true, ordre: i + 1,
}));
const CAT = Array.from({ length: 8 }, (_, i) => ({
  id: "cat_" + i, nom: "Rayon " + i, icone: "categories", couleur: "#0B5CF5",
  en_avant: true, ordre: i + 1, sous_categories: [],
}));
const ENSEIGNE = {
  id: 1, nom: "BIZZOO", slogan: "Toutes vos boutiques, une seule application",
  devise: "FCFA", indicatif: "229", site_web: "www.bizzoo.bj",
  facebook: "bizzoobenin", instagram: "", tiktok: "", youtube: "", snapchat: "",
};

/* « MONO-BOUTIQUE » N'EST PAS « UNE SEULE BOUTIQUE ». L'application
   bascule sur « multiBoutiques() », qui vaut « boutiques().length > 0 » :
   une base avec UNE boutique est déjà en mode enseigne. Le mode
   d'avant, c'est la table VIDE, et la vieille ligne unique qui fait
   les deux. Un décor à une boutique n'éprouvait donc rien. */
async function ouvrir(largeur, { unique = false } = {}) {
  const ctx = await nav.newContext({ viewport: { width: largeur, height: 1700 } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));
  await page.addInitScript(() => {
    localStorage.setItem("impact-config",
      JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
  });
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json",
      body: JSON.stringify(x) });
    if (c === "rpc/produits_populaires") return d([]);
    if (c.startsWith("categories")) return d(CAT);
    if (c.startsWith("boutiques")) return d(unique ? [] : BOU);
    if (c.startsWith("produits")) return d([]);
    if (c.startsWith("slides")) return d([]);
    if (c.startsWith("boutique")) return d([ENSEIGNE]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(2200);
  return { page, ctx };
}

/* Combien de cartes par rangée : on relève le « top » de chacune. */
const parRangee = (page) => page.evaluate(() => {
  const par = new Map();
  /* LES TUILES DE LA DA — quatre par rangée depuis la 3.50.0, à la
     demande de l'enseigne. */
  for (const c of document.querySelectorAll(".bou-tuiles .bou-tuile")) {
    const y = Math.round(c.getBoundingClientRect().top);
    par.set(y, (par.get(y) || 0) + 1);
  }
  return [...par.entries()].sort((a, b) => a[0] - b[0]).map((x) => x[1]);
});

titre("Les boutiques vont par quatre");
for (const L of [320, 360, 390, 430]) {
  const { page, ctx } = await ouvrir(L);
  const r = await parRangee(page);
  ok(r.length > 0 && r.slice(0, -1).every((n) => n === 4),
    "à " + L + " px, quatre par rangée (" + r.join("+") + ")");
  await ctx.close();
}

titre("Et rien n'y déborde, sur le plus petit téléphone");
{
  const { page, ctx } = await ouvrir(320);
  const m = await page.evaluate(() => {
    const cartes = [...document.querySelectorAll(".bou-tuiles .bou-tuile")];
    const g = document.querySelector(".bou-tuiles").getBoundingClientRect();
    let deborde = 0, hauteurs = new Set(), rondTrop = 0;
    for (const c of cartes) {
      const r = c.getBoundingClientRect();
      if (r.left < g.left - 1 || r.right > g.right + 1) deborde++;
      const rond = c.querySelector(".bou-logo").getBoundingClientRect();
      if (rond.width > r.width - 16) rondTrop++;
      hauteurs.add(Math.round(r.height));
    }
    return { deborde, rondTrop, hauteurs: [...hauteurs],
      largeurPage: document.documentElement.scrollWidth,
      rond: Math.round(cartes[0].querySelector(".bou-logo").getBoundingClientRect().width),
      carte: Math.round(cartes[0].getBoundingClientRect().width) };
  });
  ok(m.deborde === 0, "aucune carte ne sort de la grille");
  ok(m.largeurPage <= 320, "la page ne se met pas à défiler de côté (" + m.largeurPage + " px)");
  ok(m.rondTrop === 0, "l'icône garde de l'air dans sa carte (" +
    m.rond + " px dans " + m.carte + " px)");
  ok(m.hauteurs.length === 1,
    "toutes les cartes d'une rangée font la même hauteur (" + m.hauteurs.join(", ") + " px)");
  await ctx.close();
}

titre("Le slogan de BIZZOO, sous le logo");
{
  const { page, ctx } = await ouvrir(390);
  const m = await page.evaluate(() => {
    const logo = document.querySelector(".topbar .logo-mot");
    const slogan = document.querySelector(".topbar .logo-sous");
    if (!logo) return { logo: false };
    const rl = logo.getBoundingClientRect();
    const rs = slogan ? slogan.getBoundingClientRect() : null;
    return {
      logo: true, texte: slogan ? slogan.textContent.trim() : "",
      dessous: rs ? rs.top >= rl.bottom - 1 : false,
      aligne: rs ? Math.abs(rs.left - rl.left) <= 2 : false,
      /* « Coupé » se lit sur la HAUTEUR : deux lignes au plus, donc
         c'est le débordement vertical qui dit qu'on en a perdu. */
      coupe: slogan ? slogan.scrollHeight > slogan.clientHeight + 1 : false,
      large: slogan ? Math.round(slogan.scrollWidth) : 0,
      place: slogan ? Math.round(slogan.clientWidth) : 0,
      bandeau: !!document.querySelector(".topbar-slogan"),
    };
  });
  ok(m.logo, "le mot-symbole est bien là");
  ok(m.texte === "Toutes vos boutiques, une seule application",
    "le slogan de l'enseigne s'affiche (" + m.texte + ")");
  ok(m.dessous, "il est SOUS le logo, pas à côté");
  ok(m.aligne, "et calé sur son bord gauche");
  ok(!m.coupe, "il tient en entier (" + m.large + " px sur " + m.place + " px)");
  ok(!m.bandeau, "le bandeau orange ne s'y ajoute pas");
  await ctx.close();
}

titre("Une boutique ne prête pas son slogan à l'enseigne");
{
  const { page, ctx } = await ouvrir(390);
  await page.evaluate(() => { location.hash = "#/boutique/bou_0"; });
  await page.waitForTimeout(900);
  /* LA FICHE DE LA DA porte le slogan de la boutique, sous son nom —
     là où l'ancien en-tête le portait. La règle ne change pas : chez
     une boutique, c'est SON slogan, jamais celui de BIZZOO. */
  const m = await page.evaluate(() => ({
    sous: !!document.querySelector(".topbar .logo-sous"),
    enseigne: !!document.querySelector(".bou-fiche"),
    texte: (document.querySelector(".bou-fiche-slogan") || {}).textContent || "",
  }));
  ok(!m.sous, "chez une boutique, le slogan de BIZZOO disparaît");
  ok(m.enseigne, "c'est la fiche de la boutique qui prend la place");
  ok(/Slogan de IMPACT/.test(m.texte), "et c'est SON slogan à elle (" + m.texte.trim() + ")");
  await ctx.close();
}

titre("Mono-boutique : le bandeau orange garde son rôle");
{
  const { page, ctx } = await ouvrir(390, { unique: true });
  const m = await page.evaluate(() => ({
    bandeau: (document.querySelector(".topbar-slogan") || {}).textContent || "",
    sous: (document.querySelector(".topbar .logo-sous") || {}).textContent || "",
  }));
  ok(/Slogan de IMPACT/.test(m.bandeau) || /Toutes vos boutiques/.test(m.bandeau),
    "le bandeau affiche bien un slogan (" + m.bandeau.trim() + ")");
  ok(!m.sous, "et le slogan ne s'écrit pas deux fois");
  await ctx.close();
}

titre("Le site web de BIZZOO, chez le client");
{
  const { page, ctx } = await ouvrir(390);
  await page.evaluate(() => { location.hash = "#/infos"; });
  await page.waitForTimeout(900);
  const m = await page.evaluate(() => {
    const a = [...document.querySelectorAll("#vue a")]
      .find((x) => /bizzoo\.bj/.test(x.getAttribute("href") || ""));
    return { trouve: !!a, href: a ? a.getAttribute("href") : "",
      cible: a ? a.getAttribute("target") : "",
      rel: a ? a.getAttribute("rel") || "" : "" };
  });
  ok(m.trouve, "le lien du site est sur l'écran Infos");
  ok(m.href === "https://www.bizzoo.bj",
    "« www.bizzoo.bj » devient une adresse complète (" + m.href + ")");
  ok(m.cible === "_blank", "il s'ouvre à part");
  ok(/noopener/.test(m.rel), "et sans donner la main à la page ouverte");
  await ctx.close();
}

titre("Un slogan trop long se coupe, il ne fait pas grandir la barre");
{
  const court = ENSEIGNE.slogan;
  ENSEIGNE.slogan = "Toutes vos boutiques du Bénin réunies dans une seule " +
    "et même application, du matin au soir et sans jamais bouger de chez vous";
  const { page, ctx } = await ouvrir(390);
  const m = await page.evaluate(() => {
    const s = document.querySelector(".topbar .logo-sous");
    const bar = document.querySelector("#topbar");
    return { lignes: s ? Math.round(s.getBoundingClientRect().height) : 0,
      coupe: s ? s.scrollHeight > s.clientHeight + 1 : false,
      haut: Math.round(bar.getBoundingClientRect().height),
      deborde: document.documentElement.scrollWidth > 390 };
  });
  ENSEIGNE.slogan = court;
  ok(m.coupe, "il s'arrête plutôt que de pousser la barre");
  ok(m.lignes > 0 && m.lignes <= 30, "et ne dépasse pas DEUX lignes (" + m.lignes + " px)");
  ok(!m.deborde, "la page ne déborde pas de côté");
  ok(m.haut < 130, "la barre du haut reste basse (" + m.haut + " px)");
  await ctx.close();
}

titre("Ce qui n'est pas une adresse ne devient pas un lien");
{
  const vrai = ENSEIGNE.site_web;
  ENSEIGNE.site_web = "mon site";
  const { page, ctx } = await ouvrir(390);
  await page.evaluate(() => { location.hash = "#/infos"; });
  await page.waitForTimeout(900);
  const m = await page.evaluate(() => ({
    mort: [...document.querySelectorAll("#vue a")]
      .some((x) => /mon(%20| )site/i.test(x.getAttribute("href") || "")),
    ligne: /Site web/.test(document.body.innerText),
  }));
  ENSEIGNE.site_web = vrai;
  ok(!m.mort, "aucun lien « https://mon site » n'est posé");
  ok(!m.ligne, "et la ligne « Site web » ne paraît pas du tout");
  await ctx.close();
}

/* ---------- Côté boutique : le champ, l'aperçu, et ce qui part ---------- */

const MOI = "22222222-2222-2222-2222-222222222222";
titre("Dans les réglages de BIZZOO : le champ et son aperçu");
{
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1900 } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));
  const ecritures = [];
  await page.addInitScript((moi) => {
    localStorage.setItem("impact-config", JSON.stringify({
      url: "https://base-absente.invalid", cle: "cle-de-banc" }));
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: moi }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: "chef@bizzoo.bj" }));
  }, MOI);
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    if (req.method() !== "GET") {
      ecritures.push({ methode: req.method(), chemin: c + u.search,
        corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })() });
    }
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json",
      body: JSON.stringify(x) });
    if (req.method() === "PATCH") return route.fulfill({ status: 204, body: "" });
    if (c.startsWith("profils")) return d([{ id: MOI, email: "chef@bizzoo.bj",
      role: "superadministrateur", actif: true, peut_modifier_produits: true, boutique_id: null }]);
    if (c.startsWith("boutiques")) return d([]);
    if (c.startsWith("produits")) return d([]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO",
      slogan: "Toutes vos boutiques", devise: "FCFA", indicatif: "229",
      site_web: "bizzoo.bj" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1600);
  await page.evaluate(() => { location.hash = "#/reglages"; });
  await page.waitForTimeout(1800);

  const depart = await page.evaluate(() => {
    const ch = document.querySelector("#r-site");
    const ap = document.querySelector("#r-site-apercu a");
    return { present: !!ch, valeur: ch ? ch.value : "",
      apercu: ap ? ap.getAttribute("href") : "" };
  });
  ok(depart.present, "le champ « Site web » est sur l'écran");
  ok(depart.valeur === "bizzoo.bj",
    "il porte ce que la base a gardé (" + depart.valeur + ")");
  ok(depart.apercu === "https://bizzoo.bj",
    "l'aperçu montre l'adresse qui s'ouvrira (" + depart.apercu + ")");

  /* Une saisie qui n'est pas une adresse : le gérant doit le lire ICI,
     pas le découvrir chez un client. */
  await page.evaluate(() => {
    const ch = document.querySelector("#r-site");
    ch.value = "mon site";
    ch.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await page.waitForTimeout(600);
  const faux = await page.evaluate(() => ({
    lien: !!document.querySelector("#r-site-apercu a"),
    dit: (document.querySelector("#r-site-apercu") || {}).textContent || "",
  }));
  ok(!faux.lien, "une saisie qui n'est pas une adresse ne donne aucun lien");
  ok(/ne ressemble pas/i.test(faux.dit), "et l'écran le dit (" + faux.dit.trim().slice(0, 48) + "…)");

  /* Ce qui part vers la base : le nom de colonne compte. */
  await page.evaluate(() => {
    const ch = document.querySelector("#r-site");
    ch.value = "www.bizzoo.bj";
    ch.dispatchEvent(new Event("input", { bubbles: true }));
    document.querySelector("#r-enregistrer").click();
  });
  await page.waitForTimeout(1500);
  const e = ecritures.find((x) => /^boutique\?/.test(x.chemin));
  ok(!!e, "l'enregistrement part vers la base");
  ok(e && e.corps && e.corps.site_web === "www.bizzoo.bj",
    "sous le nom que la base attend : site_web (" +
    (e && e.corps ? JSON.stringify(e.corps.site_web) : "rien") + ")");
  ok(e && e.corps && e.corps.site_web !== undefined && !("siteWeb" in e.corps),
    "et pas « siteWeb », qui n'existe pas en base");
  await ctx.close();
}

await nav.close();
console.log("\n" + (echecs ? "  " + echecs + " ÉCHEC(S)" : "  Tout passe."));
process.exit(echecs ? 1 : 0);
