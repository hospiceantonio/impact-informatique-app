/* =========================================================
   La DA, éprouvée au navigateur
   =========================================================
   Trois choses se vérifient ici, et aucune ne se voit sur une
   capture d'écran :

   — que la police AFFICHÉE soit Poppins. Une @font-face qui échoue
     ne laisse aucune trace : le navigateur retombe sur la police du
     système et la page reste belle. document.fonts.check() interroge
     ce qui est réellement chargé.
   — qu'elle vienne de l'application. Une application hors connexion
     qui va chercher sa police chez Google est une application qui
     s'affiche mal dès qu'il n'y a plus de réseau — et ici, il n'y en
     a souvent pas.
   — que les couleurs soient celles de la DA, relevées sur les
     éléments eux-mêmes et non dans la feuille de style : une règle
     peut être écrite et surchargée dix lignes plus bas.

   Et sur les deux largeurs : le téléphone, et l'ordinateur — la
   boutique doit tenir sur les deux.
   ========================================================= */
/* Playwright n'est pas une dépendance du projet : les deux applications
   n'en ont aucune, et on ne va pas en ajouter une pour un banc. Il est
   donc cherché là où il se trouve, et le banc explique quoi faire s'il
   manque plutôt que de mourir sur une trace d'erreur. */
const OU_EST_PLAYWRIGHT = process.env.PLAYWRIGHT ||
  "playwright-core/index.js";
let chromium;
try {
  chromium = (await import(OU_EST_PLAYWRIGHT)).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  npm i -g playwright-core  puis  PLAYWRIGHT=<chemin> node tools/banc-da.mjs\n" +
    "  (ou PLAYWRIGHT=/chemin/vers/playwright-core/index.js)");
  process.exit(2);
}

/* Le navigateur : celui que Playwright a installé, ou celui qu'on lui
   désigne. CHROMIUM=<chemin> pour un Chromium déjà présent sur la
   machine ; sans rien, Playwright prend le sien. */
const EXE = process.env.CHROMIUM || undefined;
/* L'adresse du serveur local — « bash tools/servir.sh » sert sur 5180. */
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (vrai, quoi) => {
  if (!vrai) echecs++;
  console.log((vrai ? "  ok     " : "  ÉCHEC  ") + quoi);
};
const titre = (t) => console.log("\n== " + t + " ==");
/* Les captures : de quoi regarder de ses yeux ce que les constats ne
   voient pas — trois défauts de la charte n'ont été trouvés que là. */
const SORTIE = process.env.CAPTURES || ".";

const BLEU = "rgb(37, 80, 183)";     /* --bleu    #2550B7, le bleu de l'icône */
const ORANGE = "rgb(255, 138, 0)";   /* --orange  #FF8A00 */

const navigateur = await chromium.launch(EXE ? { executablePath: EXE } : {});

const CATEGORIES = [
  { id: "cat_mode", nom: "Mode & Vêtements", icone: "tshirt", couleur: "#6C3FBF",
    en_avant: true, ordre: 1, sous_categories: [
      { id: "sc_mode_femme", nom: "Femme", ordre: 1 }] },
  { id: "cat_hightech", nom: "High-Tech & Électronique", icone: "portable",
    couleur: "#0B5CF5", en_avant: true, ordre: 2, sous_categories: [
      { id: "sc_hightech_ordinateurs", nom: "Ordinateurs", ordre: 1 }] },
];
const BOUTIQUES = [
  { id: "bou_tech", nom: "IMPACT", secteur: "Informatique", categorie_id: "cat_hightech",
    icone: "portable", couleur: "#0B5CF5", devise: "FCFA", indicatif: "229",
    actif: true, ordre: 1 },
];
/* Cinq articles, et non un seul : une grille d'une carte ne dit rien de
   ce qu'elle fait d'une vitrine pleine, qui est le cas courant. */
const PRODUITS = [
  ["prod_hp", "Ordinateur HP", 385000],
  ["prod_souris", "Souris sans fil", 5000],
  ["prod_clavier", "Clavier azerty", 12000],
  ["prod_ecran", "Écran 24 pouces", 95000],
  ["prod_cable", "Câble HDMI", 3500],
].map(([id, nom, prix]) => ({
  id, boutique_id: "bou_tech", nom, code: id.slice(-4),
  reference: "", description: "Un matériel solide", prix, ancien_prix: null,
  categorie_id: "cat_hightech", sous_categorie_id: "sc_hightech_ordinateurs",
  stock: 5, sur_commande: false, disponible: true, en_avant: false, ordre_avant: 0,
  images: [], video: "", cree_le: "2026-09-01T08:00:00Z",
  modifie_le: "2026-09-01T08:00:00Z",
}));

/* Tout ce qui sort du site est noté : c'est la seule façon de prouver
   qu'aucune police n'est allée se chercher ailleurs.

   La base du décor est exclue, et elle seule : l'application DOIT
   appeler sa base, c'est son travail. Ce qu'on traque ici, c'est la
   police — ou l'icône, ou le script — qu'on aurait laissée chez un
   tiers, et qui manquerait le jour où il n'y a pas de réseau. */
const DECOR = "https://base-absente.invalid";
function surveiller(page, dehors) {
  page.on("request", (r) => {
    const u = r.url();
    if (!u.startsWith(BASE) && !u.startsWith(DECOR) &&
        !u.startsWith("data:") && !u.startsWith("blob:")) {
      dehors.push(u);
    }
  });
}

/* La question à laquelle une capture d'écran ne répond pas : la police
   demandée est-elle celle qui s'affiche ? */
async function policeVraie(page) {
  return page.evaluate(async () => {
    await document.fonts.ready;
    const chargees = [...document.fonts].filter((f) => f.status === "loaded");
    const h = document.querySelector("h1,h2,.topbar .titre,.logo-mot") || document.body;
    return {
      declaree: getComputedStyle(h).fontFamily,
      poppinsPrete: document.fonts.check("700 16px Poppins"),
      poids: chargees.filter((f) => f.family === "Poppins").map((f) => f.weight),
    };
  });
}

async function debordement(page) {
  return page.evaluate(() => {
    const trop = [];
    const large = document.documentElement.clientWidth;
    for (const el of document.querySelectorAll("body *")) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) continue;
      if (r.right > large + 1.5 || r.left < -1.5) {
        trop.push((el.tagName + "." + (el.className || "")).slice(0, 60));
      }
    }
    return { deborde: trop.slice(0, 5),
      defile: document.documentElement.scrollWidth > large + 1 };
  });
}

async function ouvrirClient({ largeur, hauteur, boutique = "", hash = "", nom }) {
  const ctx = await navigateur.newContext({ viewport: { width: largeur, height: hauteur } });
  const page = await ctx.newPage();
  const dehors = [];
  surveiller(page, dehors);
  page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));

  await page.addInitScript((bou) => {
    localStorage.setItem("impact-config", JSON.stringify({
      url: "https://base-absente.invalid", cle: "cle-de-banc" }));
    if (bou) localStorage.setItem("impact-boutique", bou);
    else localStorage.removeItem("impact-boutique");
  }, boutique);

  await page.route("**/rest/v1/**", (route) => {
    const chemin = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const rendre = (c) => route.fulfill({ status: 200,
      contentType: "application/json", body: JSON.stringify(c) });
    if (chemin.startsWith("categories")) return rendre(CATEGORIES);
    if (chemin.startsWith("boutiques")) return rendre(BOUTIQUES);
    if (chemin.startsWith("produits")) return rendre(PRODUITS);
    if (chemin.startsWith("boutique")) {
      return rendre([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    }
    return rendre([]);
  });

  await page.goto(BASE + "/client/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1600);
  if (boutique) {
    await page.evaluate((b) => { location.hash = "#/boutique/" + b; }, boutique);
    await page.waitForTimeout(1400);
  }
  if (hash) {
    await page.evaluate((h) => { location.hash = h; }, hash);
    await page.waitForTimeout(1400);
  }
  if (nom) await page.screenshot({ path: SORTIE + "/" + nom + ".png", fullPage: true });
  return { page, ctx, dehors };
}

async function ouvrirAdmin({ largeur, hauteur, hash = "", nom }) {
  const ctx = await navigateur.newContext({ viewport: { width: largeur, height: hauteur } });
  const page = await ctx.newPage();
  const dehors = [];
  surveiller(page, dehors);
  page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));

  await page.addInitScript(() => {
    localStorage.setItem("impact-config", JSON.stringify({
      url: "https://base-absente.invalid", cle: "cle-de-banc" }));
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." +
        b64({ sub: "aaaaaaaa-1111-1111-1111-111111111111" }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: "chef@impact.bj",
    }));
  });

  await page.route("**/rest/v1/**", (route) => {
    const chemin = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const rendre = (c) => route.fulfill({ status: 200,
      contentType: "application/json", body: JSON.stringify(c) });
    if (chemin.startsWith("profils")) {
      return rendre([{ id: "aaaaaaaa-1111-1111-1111-111111111111", email: "chef@impact.bj",
        role: "super", actif: true, peut_modifier_produits: true, boutique_id: "bou_tech" }]);
    }
    if (chemin.startsWith("categories")) return rendre(CATEGORIES);
    if (chemin.startsWith("boutiques")) return rendre(BOUTIQUES);
    if (chemin.startsWith("produits_prive")) return rendre([]);
    if (chemin.startsWith("produits")) return rendre(PRODUITS);
    return rendre([]);
  });

  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1600);
  if (hash) {
    await page.evaluate((h) => { location.hash = h; }, hash);
    await page.waitForTimeout(1400);
  }
  if (nom) await page.screenshot({ path: SORTIE + "/" + nom + ".png", fullPage: true });
  return { page, ctx, dehors };
}

/* ========================================================= */
titre("La boutique sur téléphone : la police est bien Poppins");
{
  const { page, ctx, dehors } = await ouvrirClient({ largeur: 390, hauteur: 1500,
    nom: "da-client-tel" });
  const p = await policeVraie(page);
  ok(/Poppins/.test(p.declaree), "l'écran demande Poppins");
  ok(p.poppinsPrete, "et Poppins est vraiment chargée, pas seulement demandée");
  ok(p.poids.length >= 3,
    "les graisses de la DA sont là (" + p.poids.sort().join(", ") + ")");
  ok(dehors.length === 0,
    "aucune requête hors de l'application : ni Google Fonts, ni rien" +
    (dehors.length ? " — " + dehors[0] : ""));

  /* Le logo n'est plus une image mais deux mots et deux points, tracés
     par la feuille de style : s'ils ne sont pas dessinés, rien ne le dit
     — la page reste lisible, avec un logo en une seule couleur. */
  const l = await page.evaluate(() => {
    /* Sur UN logo, et non sur toute la page : le menu latéral en porte
       un second, caché au téléphone mais bien présent dans le document,
       et un comptage global trouverait quatre points au lieu de deux. */
    const mot = document.querySelector(".topbar .logo-mot");
    if (!mot) return null;
    const bizz = mot.querySelector(".logo-bizz");
    const oo = mot.querySelector(".logo-oo");
    return { bizz: bizz ? getComputedStyle(bizz).color : "",
      oo: oo ? getComputedStyle(oo).color : "",
      mot: bizz && oo ? (bizz.innerText + oo.innerText).toLowerCase() : "",
      points: mot.querySelectorAll(".logo-points > *").length };
  });
  ok(l && l.mot === "bizzoo", "le logo écrit « bizzoo » en toutes lettres (" + l.mot + ")");
  ok(l && l.bizz === BLEU, "le « Bizz » porte le bleu de la DA (" + l.bizz + ")");
  ok(l && l.oo === ORANGE, "et les « oo » portent l'orange (" + l.oo + ")");
  ok(l && l.points === 2, "les deux points de la DA sont là (" + l.points + ")");
  await ctx.close();
}

titre("Les couleurs relevées sur les éléments, pas dans la feuille");
{
  /* Sur l'écran d'accueil il n'y a aucun bouton plein : c'est une
     vitrine, elle n'a rien à faire valider. L'écran de connexion en
     porte un, et c'est là qu'on relève le bleu de la DA. */
  const { page, ctx } = await ouvrirClient({ largeur: 390, hauteur: 1500,
    hash: "#/compte" });
  const t = await page.evaluate((B) => {
    const r = getComputedStyle(document.documentElement);
    const bar = document.querySelector(".topbar");
    /* Le bouton plein : ni la variante claire, ni l'orange des appels à
       l'action. Sur l'accueil il n'y en a pas toujours — on le cherche
       donc partout, et l'essai dit franchement s'il n'en trouve aucun. */
    const bouton = [...document.querySelectorAll(".btn")]
      .find((b) => !b.classList.contains("btn-clair") &&
                   !b.classList.contains("btn-orange") &&
                   b.getBoundingClientRect().width > 0);
    const lisible = (c) => {
      const [x, y, z] = c.match(/\d+/g).map(Number).map((v) => {
        const s = v / 255; return s <= .03928 ? s / 12.92 : ((s + .055) / 1.055) ** 2.4; });
      return .2126 * x + .7152 * y + .0722 * z;
    };
    const ic = document.querySelector(".topbar .btn-ic");
    return {
      bleu: r.getPropertyValue("--bleu").trim(),
      orange: r.getPropertyValue("--orange").trim(),
      barre: bar ? getComputedStyle(bar).backgroundColor : "",
      barreClaire: bar ? lisible(getComputedStyle(bar).backgroundColor) > .5 : false,
      icone: ic ? getComputedStyle(ic).color : "",
      iconeSombre: ic ? lisible(getComputedStyle(ic).color) < .3 : false,
      bouton: bouton ? getComputedStyle(bouton).backgroundColor : "",
    };
  }, BLEU);
  ok(t.bleu.toUpperCase() === "#2550B7", "le bleu de l'icône est posé (" + t.bleu + ")");
  ok(t.orange.toUpperCase() === "#FF8A00", "l'orange de la DA est posé (" + t.orange + ")");
  ok(t.barreClaire, "la barre du haut est claire, comme sur la DA (" + t.barre + ")");
  /* La faute qu'une capture a révélée : la barre est passée au blanc et
     ses boutons sont restés blancs — invisibles sur du blanc. */
  ok(t.iconeSombre,
    "et ses boutons y restent lisibles, pas blancs sur blanc (" + t.icone + ")");
  ok(t.bouton === BLEU, "le bouton plein est bleu (" + t.bouton + ")");
  await ctx.close();
}

titre("Le bleu de l'icône, le même partout");
{
  /* La gamme de bleus est tirée de l'icône (voir le README). Les deux
     applications, la page d'entrée du site et sa page 404 la
     partagent, jusqu'à la couleur que le navigateur donne à sa barre.
     Et aucune règle n'a gardé l'ancien bleu en dur : une ombre écrite
     en rgba(…) ne suit pas les jetons, elle se change à la main — et
     s'oublie. */
  const NUANCES = ["--bleu-900", "--bleu-800", "--bleu-700", "--bleu",
    "--bleu-400", "--bleu-300", "--bleu-100", "--bleu-50"];
  /* L'ancienne gamme de la DA, telle que le navigateur l'écrit dans une
     règle (rgb) ou dans un jeton (#…). */
  const ANCIENS = "\\b(0, 71, 217|0, 27, 82|0, 42, 128|0, 56, 168|61, 120, 236|" +
    "111, 160, 245|214, 226, 251|237, 242, 254)\\b|" +
    "#(0047d9|001b52|002a80|0038a8|3d78ec|6fa0f5|d6e2fb|edf2fe)\\b";
  const lire = async (chemin) => {
    const ctx = await navigateur.newContext({ serviceWorkers: "block" });
    const page = await ctx.newPage();
    /* Rien ne sort : il ne faut ici que les feuilles de style. */
    await page.route(/^https?:\/\/(?!127\.0\.0\.1|localhost)/, (r) => r.abort());
    await page.goto(BASE + chemin, { waitUntil: "load" });
    const r = await page.evaluate(([nuances, motif]) => {
      const s = getComputedStyle(document.documentElement);
      const jetons = {};
      for (const n of nuances) {
        const v = s.getPropertyValue(n).trim().toUpperCase();
        if (v) jetons[n] = v;
      }
      const ancien = new RegExp(motif, "i");
      const restes = [];
      for (const f of document.styleSheets) {
        let regles;
        try { regles = f.cssRules; } catch (_) { continue; }
        for (const regle of regles) {
          if (ancien.test(regle.cssText)) restes.push(regle.cssText.slice(0, 70));
        }
      }
      const meta = document.querySelector('meta[name="theme-color"]');
      const lien = document.querySelector('link[rel="manifest"]');
      return { jetons, restes, theme: meta ? meta.content.toUpperCase() : "",
        manifeste: lien ? lien.href : "" };
    }, [NUANCES, ANCIENS]);
    r.themeManifeste = "";
    if (r.manifeste) {
      const rep = await ctx.request.get(r.manifeste);
      r.themeManifeste = String((await rep.json()).theme_color || "").toUpperCase();
    }
    await ctx.close();
    return r;
  };
  const client = await lire("/client/index.html");
  const admin = await lire("/admin/index.html");
  const site = await lire("/index.html");
  const page404 = await lire("/404.html");
  const bleu = client.jetons["--bleu"];

  ok(Object.keys(client.jetons).length === NUANCES.length,
    "le client pose les huit nuances (" + Object.keys(client.jetons).length + ")");
  ok(NUANCES.every((n) => admin.jetons[n] === client.jetons[n]),
    "l'admin a exactement la même gamme");
  const communes = Object.keys(site.jetons);
  ok(communes.length >= 4 && communes.every((n) => site.jetons[n] === client.jetons[n]),
    "la page d'entrée du site aussi (" + communes.join(" ") + ")");
  ok(page404.jetons["--bleu"] === bleu, "et sa page 404 (" + page404.jetons["--bleu"] + ")");
  ok(client.theme === bleu && client.themeManifeste === bleu,
    "la barre du navigateur prend ce bleu, dans la page et dans le manifeste (" +
    client.theme + ", " + client.themeManifeste + ")");
  ok(site.theme === bleu && page404.theme === bleu,
    "sur le site et sa page 404 aussi (" + site.theme + ", " + page404.theme + ")");
  /* L'admin garde le bleu nuit de la pastille « réglages » de SON icône
     (tools/make-icons.js) : la barre de son navigateur la reprend. */
  ok(admin.theme === "#001A6E" && admin.themeManifeste === admin.theme,
    "l'admin garde le bleu nuit de sa pastille, dans la page et le manifeste (" +
    admin.theme + ", " + admin.themeManifeste + ")");
  for (const [nom, r] of [["du client", client], ["de l'admin", admin],
                          ["du site", site], ["de la page 404", page404]]) {
    ok(r.restes.length === 0, "aucune règle " + nom + " n'a gardé l'ancien bleu" +
      (r.restes.length ? " — " + r.restes[0] : ""));
  }
}

titre("L'orange de la DA, et le texte blanc qu'elle y pose");
{
  const { page, ctx } = await ouvrirClient({ largeur: 390, hauteur: 1700,
    boutique: "bou_tech", hash: "#/produit/prod_hp" });
  const t = await page.evaluate(() => {
    const o = document.querySelector(".btn-orange");
    if (!o) return null;
    const s = getComputedStyle(o);
    const lum = (c) => {
      const [x, y, z] = c.match(/\d+/g).map(Number).map((v) => {
        const s = v / 255; return s <= .03928 ? s / 12.92 : ((s + .055) / 1.055) ** 2.4; });
      return .2126 * x + .7152 * y + .0722 * z;
    };
    const a = lum(s.backgroundColor), b = lum(s.color);
    return { fond: s.backgroundColor, encre: s.color, texte: o.innerText.trim(),
      poids: Number(s.fontWeight) || 0,
      contraste: (Math.max(a, b) + .05) / (Math.min(a, b) + .05) };
  });
  ok(t !== null, "l'appel à l'action porte l'orange de la DA");
  if (t) {
    ok(t.fond === ORANGE, "c'est bien l'orange de la DA (" + t.fond + ")");
    /* LA RÈGLE A CHANGÉ, ET CE CONSTAT AVEC ELLE. Il exigeait 4,5:1, et
       la version précédente écrivait donc en sombre sur l'orange. La DA
       corrigée y pose du BLANC : c'est ce qu'on vérifie désormais.

       Le contraste n'est pas pour autant passé sous silence : il est
       mesuré et AFFICHÉ à chaque passage, pour qu'on sache toujours ce
       que coûte ce choix. S'il remontait — texte revenu au sombre —, le
       premier constat tomberait : c'est lui qui dit ce que veut la DA. */
    ok(t.encre === "rgb(255, 255, 255)",
      "son texte est blanc, comme sur la DA (" + t.encre + ")");
    ok(t.poids >= 700, "et gras, ce qui se lit mieux au soleil qu'un texte mi-gras (" +
      t.poids + ")");
    console.log("  info   contraste du blanc sur l'orange : " + t.contraste.toFixed(2) +
      ":1 — sous le seuil de 4,5:1, choix de la DA (voir --orange-texte)");
  }
  await ctx.close();
}

titre("Rien ne déborde, du téléphone à l'ordinateur");
for (const [l, h, quoi] of [[360, 1500, "un petit téléphone (360)"],
                            [390, 1500, "un téléphone courant (390)"],
                            [768, 1400, "une tablette (768)"],
                            [1440, 1000, "un ordinateur (1440)"]]) {
  const { page, ctx } = await ouvrirClient({ largeur: l, hauteur: h });
  const d = await debordement(page);
  ok(!d.defile && d.deborde.length === 0,
    "sur " + quoi + (d.deborde.length ? " — " + d.deborde.join(", ") : ""));
  await ctx.close();
}

titre("Sur ordinateur, la boutique s'étale au lieu de flotter");
{
  const { page, ctx } = await ouvrirClient({ largeur: 1440, hauteur: 1000,
    boutique: "bou_tech", hash: "#/produits", nom: "da-client-ordi" });
  const t = await page.evaluate(() => {
    const bar = document.querySelector(".tabbar");
    const vue = document.querySelector(".vue");
    const rb = bar ? bar.getBoundingClientRect() : null;
    const rv = vue ? vue.getBoundingClientRect() : null;
    return {
      menuAGauche: rb ? rb.left < 5 && rb.height > 400 : false,
      largeurMenu: rb ? Math.round(rb.width) : 0,
      vueDegagee: rb && rv ? rv.left >= rb.right - 1 : false,
      largeurVue: rv ? Math.round(rv.width) : 0,
      colonnes: (() => {
        const g = document.querySelector(".p-grille");
        return g ? getComputedStyle(g).gridTemplateColumns.split(" ").length : 0;
      })(),
    };
  });
  ok(t.menuAGauche,
    "la barre du bas devient un menu sur le bord gauche (" + t.largeurMenu + " px)");
  ok(t.vueDegagee, "et le contenu ne passe pas dessous");
  /* Le seuil est à 900 et non à 700 : la colonne du téléphone fait déjà
     720 px, si bien qu'un seuil à 700 se laisserait contenter par elle.
     Un essai qu'on ne peut pas faire échouer ne prouve rien. */
  ok(t.largeurVue > 900,
    "le catalogue s'étale (" + t.largeurVue + " px de large, contre 720 au téléphone)");
  ok(t.colonnes === 4, "quatre produits de front (" + t.colonnes + ")");

  /* En haut du menu, le logo de la charte et non l'icône de
     l'application : celle-ci est un dessin fait pour un écran
     d'accueil, et posée là elle donnait deux marques l'une à côté de
     l'autre. Le piège tient en une ligne — une règle de couleur sur
     « .tabbar-marque span » repeint « Bizz » ET « oo » de la même
     teinte, et le logo redevient monochrome sans que rien ne casse. */
  const m = await page.evaluate(() => {
    const marque = document.querySelector(".tabbar-marque");
    if (!marque) return null;
    const bizz = marque.querySelector(".logo-bizz");
    const oo = marque.querySelector(".logo-oo");
    return {
      visible: getComputedStyle(marque).display !== "none",
      image: !!marque.querySelector("img"),
      bizz: bizz ? getComputedStyle(bizz).color : "",
      oo: oo ? getComputedStyle(oo).color : "",
    };
  });
  ok(m && m.visible, "le menu s'ouvre sur la marque");
  ok(m && !m.image, "et c'est le logo écrit, pas l'icône de l'application");
  ok(m && m.bizz === BLEU && m.oo === ORANGE,
    "qui garde ses deux couleurs (" + (m ? m.bizz + " / " + m.oo : "") + ")");
  await ctx.close();
}

titre("Le poste de l'enseigne : même police, même palette");
{
  const { page, ctx, dehors } = await ouvrirAdmin({ largeur: 1440, hauteur: 1100,
    nom: "da-admin-ordi" });
  const p = await policeVraie(page);
  ok(p.poppinsPrete, "Poppins est chargée là aussi");
  ok(dehors.length === 0,
    "et sans rien aller chercher dehors" + (dehors.length ? " — " + dehors[0] : ""));
  const t = await page.evaluate(() => {
    const r = getComputedStyle(document.documentElement);
    const bizz = document.querySelector(".logo-bizz");
    const oo = document.querySelector(".logo-oo");
    return { bleu: r.getPropertyValue("--bleu").trim(),
      bizz: bizz ? getComputedStyle(bizz).color : "",
      oo: oo ? getComputedStyle(oo).color : "" };
  });
  ok(t.bleu.toUpperCase() === "#2550B7", "le même bleu que la boutique");
  ok(t.bizz === BLEU && t.oo === ORANGE, "et le même logo, en deux couleurs");
  const m = await page.evaluate(() => {
    const marque = document.querySelector(".tabbar-marque");
    if (!marque) return null;
    const bizz = marque.querySelector(".logo-bizz");
    const oo = marque.querySelector(".logo-oo");
    return { image: !!marque.querySelector("img"),
      bizz: bizz ? getComputedStyle(bizz).color : "",
      oo: oo ? getComputedStyle(oo).color : "",
      role: (marque.querySelector(".marque-role") || {}).innerText || "" };
  });
  ok(m && !m.image, "le menu s'ouvre sur le logo écrit, pas sur l'icône");
  ok(m && m.bizz === BLEU && m.oo === ORANGE,
    "qui garde ses deux couleurs (" + (m ? m.bizz + " / " + m.oo : "") + ")");
  ok(m && /admin/i.test(m.role),
    "et le poste de l'enseigne se distingue de la boutique (" +
    (m ? m.role : "") + ")");
  const d = await debordement(page);
  ok(!d.defile && d.deborde.length === 0,
    "rien ne déborde" + (d.deborde.length ? " — " + d.deborde.join(", ") : ""));
  await ctx.close();
}

titre("Le poste de l'enseigne tient aussi sur un téléphone");
{
  const { page, ctx } = await ouvrirAdmin({ largeur: 390, hauteur: 1600,
    nom: "da-admin-tel" });
  const d = await debordement(page);
  ok(!d.defile && d.deborde.length === 0,
    "rien ne déborde à 390 px" + (d.deborde.length ? " — " + d.deborde.join(", ") : ""));
  const t = await page.evaluate(() => {
    const bar = document.querySelector(".topbar");
    const ic = document.querySelector(".topbar .btn-ic");
    const lum = (c) => {
      const [x, y, z] = c.match(/\d+/g).map(Number).map((v) => {
        const s = v / 255; return s <= .03928 ? s / 12.92 : ((s + .055) / 1.055) ** 2.4; });
      return .2126 * x + .7152 * y + .0722 * z;
    };
    if (!bar) return null;
    const a = lum(getComputedStyle(bar).backgroundColor);
    const b = ic ? lum(getComputedStyle(ic).color) : null;
    return { claire: a > .5,
      contraste: b === null ? null : (Math.max(a, b) + .05) / (Math.min(a, b) + .05) };
  });
  ok(t && t.claire, "la barre du haut y est claire aussi");
  ok(t && t.contraste !== null && t.contraste >= 3,
    "et ses boutons s'y détachent" + (t && t.contraste ?
      " (" + t.contraste.toFixed(2) + ":1)" : ""));
  /* LES CARTES-LIENS DE L'ACCUEIL SONT DES BLOCS. Un « a » reste en
     ligne si rien ne dit le contraire : son fond blanc ne couvrait que
     des bouts de ligne, et le titre de la carte Stock flottait sur la
     page, un rectangle blanc au bord. Aucun constat ne le voyait — la
     carte était là, avec le bon texte. On mesure donc que la carte
     enveloppe bien son titre. */
  const c = await page.evaluate(() => [...document.querySelectorAll(".vue a.carte")].map((a) => {
    const r = a.getBoundingClientRect();
    /* Le titre, ou à défaut le premier élément : la carte de la
       boutique active n'a pas de titre. */
    const dedans = a.querySelector(".carte-titre") || a.firstElementChild;
    if (!dedans) return { id: a.id || a.className, display: getComputedStyle(a).display, enveloppe: true };
    const rt = dedans.getBoundingClientRect();
    return { id: a.id || a.className, display: getComputedStyle(a).display,
      enveloppe: rt.top >= r.top - 1 && rt.bottom <= r.bottom + 1 && r.height > rt.height };
  }));
  const plates = c.filter((x) => x.display === "inline" || !x.enveloppe);
  ok(c.some((x) => x.id === "carte-stock"), "la carte Stock est sur l'accueil (" + c.length + " cartes-liens)");
  ok(plates.length === 0, "et chaque carte-lien enveloppe son titre" +
    (plates.length ? " — " + plates.map((x) => x.id + " : " + x.display).join(", ") : ""));
  await ctx.close();
}

titre("La police est servie par l'application, pas par le réseau");
{
  /* Demandé par requête et non par navigation : ouvrir un .woff2 dans un
     onglet déclenche un téléchargement, pas un chargement de page. */
  const ctx = await navigateur.newContext();
  const r = await ctx.request.get(BASE + "/client/polices/poppins-700.woff2");
  ok(r.status() === 200, "le fichier est bien dans l'application");
  const taille = (await r.body()).length;
  ok(taille > 3000 && taille < 60000,
    "et il pèse ce qu'il doit peser (" + Math.round(taille / 1024) + " ko)");
  /* Une application hors connexion qui ne met pas sa police en cache
     perd sa typographie dès la première panne de réseau. */
  const sw = await (await ctx.request.get(BASE + "/client/sw.js")).text();
  ok(/polices\/poppins-700\.woff2/.test(sw),
    "le service worker la garde hors connexion");
  const swa = await (await ctx.request.get(BASE + "/admin/sw.js")).text();
  ok(/polices\/poppins-700\.woff2/.test(swa), "celui de l'enseigne aussi");
  await ctx.close();
}

await navigateur.close();
console.log("\n" + (echecs ? "  " + echecs + " ÉCHEC(S)" : "  Tout passe."));
process.exit(echecs ? 1 : 0);
