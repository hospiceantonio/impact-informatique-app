/* =========================================================
   La mise en ligne : ce qui part, et ce qui marche une fois parti
   =========================================================
   CE QUE CE BANC GARDE. Le site part à deux adresses — l'hébergement
   de www.bizzoomarket.com, et GitHub Pages sous le nom du dépôt — et
   ce qui casse à ce moment-là ne se voit pas en développant :

     1. CE QUI PART. Une liste blanche (tools/assembler-site.sh) : le
        README, skills/, les scripts n'ont rien à faire en ligne, et
        l'assemblage d'avant les publiait ;
     2. TOUT CE QU'UNE PAGE DEMANDE EXISTE dans le site assemblé — pas
        seulement dans le dépôt ;
     3. CE QUE VOIENT LES MOTEURS ET LES MESSAGERIES : adresse
        officielle, aperçu de partage en adresses entières, l'admin hors
        des moteurs, robots et sitemap ;
     4. LE ZIP DE L'HÉBERGEMENT : le même site, et son .htaccess ;
     5. LE SITE S'OUVRE aux deux adresses, sous-dossier compris, et sa
        page 404 ramène au bon endroit depuis n'importe quelle profondeur ;
     6. LE LIEN « MOT DE PASSE OUBLIÉ » ABOUTIT — il arrivait sur le site
        et n'y trouvait personne pour le lire ;
     7. LE .htaccess SUR UN VRAI APACHE, réglé comme les hébergeurs les
        plus avares (« AllowOverride FileInfo ») : un .htaccess fautif,
        c'est tout le site en erreur 500. Sauté si Apache est absent.

   Aucune requête ne sort : les deux adresses et la base sont servies
   par le banc lui-même.

     PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-mise-en-ligne.mjs
   ========================================================= */
import { execFileSync, spawn } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import https from "node:https";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-mise-en-ligne.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
/* Le dépôt à éprouver : celui-ci, ou une copie sabotée (DEPOT=…). */
const DEPOT = process.env.DEPOT || path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), "bizzoo-mise-en-ligne-"));
const SITE = path.join(TMP, "site");
const DOMAINE = "https://www.bizzoomarket.com";
const PAGES = "https://hospiceantonio.github.io";
const PREFIXE_PAGES = "/impact-informatique-app";

/* ------------------------------------------------------------------ */
titre("1. Ce qui part en ligne : la liste blanche, et rien d'autre");
let assemble = false;
try {
  const s = execFileSync("bash", [path.join(DEPOT, "tools/assembler-site.sh"), SITE],
    { cwd: DEPOT, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  assemble = true;
  ok(true, "l'assemblage passe (" + s.trim() + ")");
} catch (e) {
  ok(false, "l'assemblage passe — " + String(e.stderr || e.message).trim());
}
const existe = (p) => fs.existsSync(path.join(SITE, p));
for (const p of ["index.html", "404.html", "robots.txt", "sitemap.xml", "vitrine/partage.jpg",
  "client/index.html", "admin/index.html", "apk/bizzoo-client.apk"]) {
  ok(existe(p), "en ligne : " + p);
}
/* LE CONSTAT QUI A OUVERT CE CHANTIER : le README et skills/ étaient
   publiés avec le reste, par une copie « tout sauf ». */
for (const p of ["README.md", "skills", "DEMARRER-BIZZOO.bat", "serve.ps1", "tools", "supabase",
  "android", "captures", ".github", ".gitignore", ".gitattributes", "hebergement", ".htaccess"]) {
  ok(!existe(p), "absent : " + p);
}
if (!assemble) {
  console.log("\nSans site assemblé, le reste n'a rien à éprouver.");
  process.exit(1);
}

/* ------------------------------------------------------------------ */
titre("2. Tout ce qu'une page demande existe dans le site");
{
  const manquants = [];
  const verifier = (depuis, cible) => {
    const propre = cible.split("#")[0].split("?")[0];
    if (!propre) return;
    let p = path.join(path.dirname(path.join(SITE, depuis)), decodeURIComponent(propre));
    if (propre.endsWith("/")) p = path.join(p, "index.html");
    if (!fs.existsSync(p)) manquants.push(depuis + " → " + cible);
  };
  const externe = (v) => /^(https?:|mailto:|tel:|data:|javascript:|#|\/\/)/i.test(v) || v.includes("${");
  for (const page of ["index.html", "client/index.html", "admin/index.html"]) {
    const html = fs.readFileSync(path.join(SITE, page), "utf8");
    for (const m of html.matchAll(/\s(?:src|href)="([^"]+)"/g)) {
      if (!externe(m[1])) verifier(page, m[1]);
    }
    for (const m of html.matchAll(/url\(\s*['"]?([^'")]+)['"]?\s*\)/g)) {
      if (!externe(m[1])) verifier(page, m[1]);
    }
  }
  for (const feuille of ["client/styles.css", "admin/styles.css"]) {
    const css = fs.readFileSync(path.join(SITE, feuille), "utf8");
    for (const m of css.matchAll(/url\(\s*['"]?([^'")]+)['"]?\s*\)/g)) {
      if (!externe(m[1])) verifier(feuille, m[1]);
    }
  }
  for (const manifeste of ["client/manifest.webmanifest", "admin/manifest.webmanifest"]) {
    const m = JSON.parse(fs.readFileSync(path.join(SITE, manifeste), "utf8"));
    for (const icone of m.icons || []) verifier(manifeste, icone.src);
    verifier(manifeste, m.start_url);
  }
  ok(!manquants.length, "aucune adresse relative ne mène à un fichier absent" +
    (manquants.length ? " : " + manquants.slice(0, 6).join(" ; ") : ""));

  /* La page 404 s'affiche à n'importe quelle profondeur : une adresse
     relative y mènerait n'importe où. Elle n'en a donc aucune. */
  const p404 = fs.readFileSync(path.join(SITE, "404.html"), "utf8");
  const relatifs = [...p404.matchAll(/\s(?:src|href)="([^"]+)"/g)].map((m) => m[1])
    .filter((v) => !v.startsWith("/") && !externe(v));
  ok(!relatifs.length, "la page 404 n'a aucune adresse relative" +
    (relatifs.length ? " (" + relatifs.join(", ") + ")" : ""));
}

/* ------------------------------------------------------------------ */
titre("3. Ce que voient les moteurs de recherche et les messageries");
{
  const meta = (html, attr, nom) => {
    const m = html.match(new RegExp("<meta\\s+" + attr + '="' + nom + '"\\s+content="([^"]*)"'));
    return m ? m[1] : "";
  };
  const lien = (html, rel) => {
    const m = html.match(new RegExp('<link\\s+rel="' + rel + '"\\s+href="([^"]*)"'));
    return m ? m[1] : "";
  };
  const local = (url) => {
    if (!url.startsWith(DOMAINE + "/")) return null;
    let p = url.slice(DOMAINE.length + 1);
    if (!p || p.endsWith("/")) p += "index.html";
    return path.join(SITE, p);
  };
  const vitrine = fs.readFileSync(path.join(SITE, "index.html"), "utf8");
  const client = fs.readFileSync(path.join(SITE, "client/index.html"), "utf8");
  const admin = fs.readFileSync(path.join(SITE, "admin/index.html"), "utf8");

  ok(lien(vitrine, "canonical") === DOMAINE + "/", "la vitrine désigne son adresse officielle");
  ok(lien(client, "canonical") === DOMAINE + "/client/", "la boutique aussi");
  /* L'APERÇU WHATSAPP : une image en chemin relatif est ignorée, et le
     lien partagé part sans image. */
  for (const [nom, html] of [["vitrine", vitrine], ["boutique", client]]) {
    const image = meta(html, "property", "og:image");
    ok(/^https:\/\//.test(image) && local(image) && fs.existsSync(local(image)),
      nom + " : l'image de l'aperçu est une adresse entière, qui existe (" + image + ")");
    ok(/^https:\/\//.test(meta(html, "property", "og:url")), nom + " : og:url est entière");
  }
  ok(meta(vitrine, "name", "twitter:card") === "summary_large_image", "l'aperçu est en grand format");
  const jpeg = fs.readFileSync(path.join(SITE, "vitrine/partage.jpg"));
  const taille = (() => {
    let i = 2;
    while (i < jpeg.length && jpeg[i] === 0xFF) {
      const m = jpeg[i + 1];
      if (m >= 0xC0 && m <= 0xCF && ![0xC4, 0xC8, 0xCC].includes(m)) {
        return jpeg.readUInt16BE(i + 7) + "×" + jpeg.readUInt16BE(i + 5);
      }
      i += 2 + jpeg.readUInt16BE(i + 2);
    }
    return "?";
  })();
  /* WhatsApp renonce à l'image au-delà d'environ 300 Ko. */
  ok(taille === "1200×630" && jpeg.length < 300 * 1024,
    "l'image de partage fait 1200×630 et moins de 300 Ko (" + taille + ", " +
    Math.round(jpeg.length / 1024) + " Ko)");
  ok(/noindex/.test(meta(admin, "name", "robots")), "l'espace de gestion est hors des moteurs");
  ok(!/noindex/.test(meta(vitrine, "name", "robots")) && !/noindex/.test(meta(client, "name", "robots")),
    "la vitrine et la boutique, elles, s'indexent");
  const robots = fs.readFileSync(path.join(SITE, "robots.txt"), "utf8");
  ok(/^Disallow: \/admin\/$/m.test(robots) &&
    robots.includes("Sitemap: " + DOMAINE + "/sitemap.xml"), "robots.txt écarte /admin/ et cite le sitemap");
  const plan = fs.readFileSync(path.join(SITE, "sitemap.xml"), "utf8");
  const adresses = [...plan.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
  ok(adresses.length >= 2 && adresses.every((a) => local(a) && fs.existsSync(local(a))),
    "chaque adresse du sitemap mène à une page (" + adresses.join(", ") + ")");
  const description = JSON.parse(fs.readFileSync(path.join(SITE, "client/manifest.webmanifest"), "utf8"))
    .description;
  ok(/Mobile Money/.test(description) && !/par WhatsApp\./.test(description),
    "l'application installée se décrit comme elle est : Mobile Money");
}

/* ------------------------------------------------------------------ */
titre("4. Le zip de l'hébergement");
const HEB = path.join(TMP, "hebergement");
{
  const zip = path.join(TMP, "bizzoo-site.zip");
  let fait = false;
  try {
    execFileSync("bash", [path.join(DEPOT, "tools/assembler-site.sh"), "--hebergement", zip],
      { cwd: DEPOT, stdio: ["ignore", "pipe", "pipe"] });
    fait = fs.existsSync(zip);
  } catch (e) { /* constaté juste dessous */ }
  ok(fait, "le zip se fabrique");
  if (fait) {
    execFileSync("unzip", ["-q", zip, "-d", HEB]);
    ok(fs.existsSync(path.join(HEB, ".htaccess")), "il porte le .htaccess, à sa racine");
    ok(fs.existsSync(path.join(HEB, "index.html")) && fs.existsSync(path.join(HEB, "client/index.html")),
      "le site est à plat : index.html à la racine, pas dans un sous-dossier");
    const compter = (d) => fs.readdirSync(d, { withFileTypes: true })
      .reduce((n, e) => n + (e.isDirectory() ? compter(path.join(d, e.name)) : 1), 0);
    ok(compter(HEB) === compter(SITE) + 1, "et rien d'autre que le site de GitHub Pages, plus ce fichier");
  }
}

/* ------------------------------------------------------------------ */
/* Un hébergement de poche, fidèle à ce que font Apache et GitHub Pages :
   un dossier sans « / » final est redirigé, un dossier donne son
   index.html, une adresse inconnue la page 404 — avec le statut 404. */
const TYPES = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".json": "application/json",
  ".webmanifest": "application/manifest+json", ".png": "image/png", ".jpg": "image/jpeg",
  ".svg": "image/svg+xml", ".woff2": "font/woff2", ".txt": "text/plain", ".xml": "application/xml",
  ".apk": "application/vnd.android.package-archive",
};
function servir(route, prefixe) {
  const url = new URL(route.request().url());
  let chemin = decodeURIComponent(url.pathname);
  const introuvable = () => route.fulfill({ status: 404, contentType: TYPES[".html"],
    body: fs.readFileSync(path.join(SITE, "404.html")) });
  if (prefixe) {
    if (chemin !== prefixe && !chemin.startsWith(prefixe + "/")) return introuvable();
    chemin = chemin.slice(prefixe.length) || "/";
  }
  let fichier = path.join(SITE, chemin);
  if (!fichier.startsWith(SITE)) return introuvable();
  if (fs.existsSync(fichier) && fs.statSync(fichier).isDirectory()) {
    if (!url.pathname.endsWith("/")) {
      return route.fulfill({ status: 301, headers: { location: url.pathname + "/" + url.search } });
    }
    fichier = path.join(fichier, "index.html");
  }
  if (!fs.existsSync(fichier) || !fs.statSync(fichier).isFile()) return introuvable();
  return route.fulfill({ status: 200, contentType: TYPES[path.extname(fichier)] || "application/octet-stream",
    body: fs.readFileSync(fichier) });
}

/* La base, servie par le banc. Le journal garde ce que l'application a
   demandé à l'authentification. */
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const JETON = b64({ alg: "HS256", typ: "JWT" }) + "." + b64({
  sub: "5b2f6c1e-0000-4000-8000-00000000b122", email: "awa@exemple.bj", phone: "",
  role: "authenticated", exp: Math.floor(Date.now() / 1000) + 3600,
}) + ".signature-de-banc";
const RETOUR = "access_token=" + JETON + "&expires_at=" + (Math.floor(Date.now() / 1000) + 3600) +
  "&expires_in=3600&refresh_token=r1&token_type=bearer&type=recovery";
const PERIME = "error=access_denied&error_code=otp_expired" +
  "&error_description=Email+link+is+invalid+or+has+expired";

const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
async function ouvrir(journal = [], reglages = {}) {
  /* Pas de service worker : il servirait ses fichiers sans passer par
     le banc, et l'on n'éprouverait plus le site assemblé. */
  const ctx = await nav.newContext({ viewport: { width: 390, height: 860 }, serviceWorkers: "block" });
  const erreurs = [];
  await ctx.addInitScript(() => {
    localStorage.setItem("impact-config", JSON.stringify({
      url: "https://base-absente.invalid", cle: "cle-de-banc" }));
  });
  await ctx.route(DOMAINE + "/**", (r) => servir(r, ""));
  await ctx.route(PAGES + "/**", (r) => servir(r, PREFIXE_PAGES));
  await ctx.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha", secteur: "Informatique",
      icone: "magasin", couleur: "#0047D9", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await ctx.route("**/auth/v1/**", async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    journal.push({ chemin: url.pathname.replace(/^.*\/auth\/v1\//, "") + url.search,
      methode: req.method(), corps: req.postData() || "", autorisation: req.headers().authorization || "" });
    if (url.pathname.endsWith("/user") && req.method() === "PUT") {
      if (reglages.memeMotDePasse) {
        return route.fulfill({ status: 422, contentType: "application/json", body: JSON.stringify({
          code: 422, error_code: "same_password",
          msg: "New password should be different from the old password." }) });
      }
      return route.fulfill({ status: 200, contentType: "application/json",
        body: JSON.stringify({ id: "5b2f6c1e", email: "awa@exemple.bj" }) });
    }
    if (url.search.includes("grant_type=refresh_token")) {
      return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({
        access_token: JETON, refresh_token: "r2", expires_in: 3600 }) });
    }
    return route.fulfill({ status: 200, contentType: "application/json", body: "{}" });
  });
  await ctx.route("**/storage/v1/**", (r) => r.fulfill({ status: 404, body: "" }));
  const page = await ctx.newPage();
  page.on("pageerror", (e) => erreurs.push(e.message));
  return { page, ctx, erreurs };
}
const attendre = (page, ms = 1400) => page.waitForTimeout(ms);

/* ------------------------------------------------------------------ */
titre("5. Le site s'ouvre, à ses deux adresses");
{
  const { page, ctx, erreurs } = await ouvrir();
  await page.goto(DOMAINE + "/", { waitUntil: "load" });
  await attendre(page, 600);
  const images = await page.evaluate(() => [...document.images]
    .map((i) => ({ src: i.getAttribute("src"), ok: i.complete && i.naturalWidth > 0 })));
  ok(images.length >= 4 && images.every((i) => i.ok),
    "www.bizzoomarket.com : la vitrine et ses " + images.length + " images");
  await page.click('.entete a[href="client/"]');
  await attendre(page);
  ok(page.url() === DOMAINE + "/client/" &&
    await page.evaluate(() => !!document.querySelector("#tabbar") && document.getElementById("vue").children.length > 0),
    "« Ouvrir la boutique » ouvre l'application (" + page.url() + ")");
  await page.goto(DOMAINE + "/admin/", { waitUntil: "load" });
  await attendre(page, 900);
  ok(await page.evaluate(() => document.body.innerText.length > 20), "l'espace de gestion s'ouvre");
  ok(!erreurs.length, "sans erreur JavaScript" + (erreurs.length ? " : " + erreurs.join(" | ") : ""));

  /* LA PAGE 404, À N'IMPORTE QUELLE PROFONDEUR : ses liens partent de la
     racine, et ses polices aussi. */
  const r404 = await page.goto(DOMAINE + "/une/adresse/qui/n-existe-pas", { waitUntil: "load" });
  await attendre(page, 500);
  const l404 = await page.evaluate(() => ({
    texte: document.body.innerText,
    liens: [...document.querySelectorAll("a[data-lien]")].map((a) => a.href),
    police: document.fonts.check("700 20px Poppins"),
  }));
  ok(r404.status() === 404 && /Page introuvable/.test(l404.texte), "une adresse inconnue répond 404, avec la page de BIZZOO");
  ok(l404.liens.join(",") === DOMAINE + "/client/," + DOMAINE + "/",
    "et ses liens ramènent à la boutique et à l'accueil (" + l404.liens.join(", ") + ")");
  ok(l404.police, "dans la police de la DA, même à cette profondeur");
  await ctx.close();
}
{
  /* GITHUB PAGES : le même site, sous le nom du dépôt. */
  const { page, ctx, erreurs } = await ouvrir();
  await page.goto(PAGES + PREFIXE_PAGES + "/", { waitUntil: "load" });
  await attendre(page, 600);
  ok(await page.evaluate(() => [...document.images].every((i) => i.complete && i.naturalWidth > 0)),
    "GitHub Pages : la vitrine s'ouvre sous le nom du dépôt, images comprises");
  await page.goto(PAGES + PREFIXE_PAGES + "/client/", { waitUntil: "load" });
  await attendre(page);
  ok(await page.evaluate(() => document.getElementById("vue").children.length > 0), "et la boutique aussi");
  await page.goto(PAGES + PREFIXE_PAGES + "/rien/ici", { waitUntil: "load" });
  await attendre(page, 400);
  const liens = await page.evaluate(() => [...document.querySelectorAll("a[data-lien]")].map((a) => a.href));
  ok(liens[0] === PAGES + PREFIXE_PAGES + "/client/",
    "sa page 404 ramène à la boutique du dépôt, pas à la racine de github.io (" + liens[0] + ")");
  ok(!erreurs.length, "sans erreur JavaScript" + (erreurs.length ? " : " + erreurs.join(" | ") : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("6. Le lien « mot de passe oublié » aboutit");
{
  const journal = [];
  const { page, ctx, erreurs } = await ouvrir(journal);
  await page.goto(DOMAINE + "/client/#" + RETOUR, { waitUntil: "load" });
  await attendre(page);
  const m = await page.evaluate(() => ({
    hash: location.hash, adresse: location.href,
    titre: (document.querySelector(".topbar h1") || {}).textContent || "",
    retour: !!document.querySelector('.topbar [data-action="retour"]'),
    texte: document.getElementById("vue").textContent,
    session: JSON.parse(localStorage.getItem("bizzoo-session") || "null"),
  }));
  ok(m.hash === "#/nouveau-mot-de-passe", "le lien ouvre « Nouveau mot de passe » (" + m.hash + ")");
  /* LE JETON QUITTE LA BARRE D'ADRESSE : laissé là, il finit dans une
     capture d'écran ou un lien partagé. */
  ok(!/access_token|refresh_token/.test(m.adresse), "et le jeton a quitté la barre d'adresse");
  ok(m.titre.trim() === "Nouveau mot de passe" && /awa@exemple\.bj/.test(m.texte),
    "l'écran dit pour quel compte");
  ok(!m.retour, "sans flèche de retour : l'écran d'avant rejouerait un lien consommé");
  ok(!!m.session && m.session.access_token === JETON && m.session.email === "awa@exemple.bj",
    "la session du lien est gardée");

  const puts = () => journal.filter((j) => j.methode === "PUT" && j.chemin.startsWith("user"));
  await page.fill("#cp-nouveau", "abc");
  await page.fill("#cp-encore", "abc");
  await page.click("#cp-changer");
  await attendre(page, 300);
  ok(!puts().length, "trop court : rien n'est envoyé");
  await page.fill("#cp-nouveau", "nouveau-secret-1");
  await page.fill("#cp-encore", "nouveau-secret-2");
  await page.click("#cp-changer");
  await attendre(page, 300);
  ok(!puts().length, "deux saisies différentes : rien n'est envoyé");
  await page.fill("#cp-encore", "nouveau-secret-1");
  await page.click("#cp-changer");
  await attendre(page, 900);
  const envoi = puts()[0] || {};
  ok(puts().length === 1 && JSON.parse(envoi.corps || "{}").password === "nouveau-secret-1",
    "le mot de passe part une fois, à Supabase");
  ok(envoi.autorisation === "Bearer " + JETON, "au nom du compte du lien");
  ok(await page.evaluate(() => location.hash) === "#/compte", "puis « Mon compte » s'ouvre");
  ok(!erreurs.length, "sans erreur JavaScript" + (erreurs.length ? " : " + erreurs.join(" | ") : ""));
  await ctx.close();
}
{
  /* Le même mot de passe qu'avant : Supabase refuse, l'écran le dit. */
  const { page, ctx } = await ouvrir([], { memeMotDePasse: true });
  await page.goto(DOMAINE + "/client/#" + RETOUR, { waitUntil: "load" });
  await attendre(page);
  await page.fill("#cp-nouveau", "ancien-secret");
  await page.fill("#cp-encore", "ancien-secret");
  await page.click("#cp-changer");
  await attendre(page, 700);
  const r = await page.evaluate(() => ({ toast: (document.querySelector(".toast") || {}).textContent || "",
    actif: !document.getElementById("cp-changer").disabled, hash: location.hash }));
  ok(/mot de passe actuel/.test(r.toast) && r.actif && r.hash === "#/nouveau-mot-de-passe",
    "l'ancien mot de passe : refusé en français, et l'on peut réessayer (" + r.toast + ")");
  await ctx.close();
}
{
  /* Le lien expiré, ou déjà servi. */
  const { page, ctx } = await ouvrir();
  await page.goto(DOMAINE + "/client/#" + PERIME, { waitUntil: "load" });
  await attendre(page);
  const r = await page.evaluate(() => ({ hash: location.hash, adresse: location.href,
    alerte: (document.getElementById("cp-lien-perime") || {}).textContent || "",
    formulaire: !!document.getElementById("cp-envoyer") }));
  ok(r.hash === "#/mot-de-passe?lien=perime" && /n'est plus valable/.test(r.alerte) && r.formulaire,
    "un lien périmé le dit, et propose d'en demander un autre");
  ok(!/otp_expired|error_description/.test(r.adresse), "et l'adresse est nettoyée");
  await ctx.close();
}
{
  /* LA VITRINE RENVOIE LE LIEN : si Supabase ramène à la racine du
     site plutôt qu'à /client/, le lien aboutit quand même. */
  const { page, ctx } = await ouvrir();
  await page.goto(DOMAINE + "/#" + RETOUR, { waitUntil: "load" });
  await attendre(page, 1800);
  const r = await page.evaluate(() => location.pathname + location.hash);
  ok(r === "/client/#/nouveau-mot-de-passe", "arrivé sur la vitrine, le lien est passé à l'application (" + r + ")");
  await ctx.close();
}
{
  /* Sans lien, l'écran n'a rien à changer. */
  const { page, ctx } = await ouvrir();
  await page.goto(DOMAINE + "/client/#/nouveau-mot-de-passe", { waitUntil: "load" });
  await attendre(page);
  ok(await page.evaluate(() => location.hash) === "#/mot-de-passe?lien=perime",
    "ouvert sans lien, l'écran renvoie en demander un");
  await ctx.close();
}
{
  /* Au rafraîchissement de la session, le numéro reste : sans lui, un
     compte créé par SMS affichait un identifiant vide au bout d'une heure. */
  const { page, ctx } = await ouvrir();
  await ctx.addInitScript(() => {
    localStorage.setItem("bizzoo-session", JSON.stringify({ access_token: "vieux", refresh_token: "r1",
      expire_a: Date.now() - 1000, email: "", tel: "22997000000" }));
  });
  await page.goto(DOMAINE + "/client/", { waitUntil: "load" });
  await attendre(page, 1500);
  const apres = await page.evaluate(async () => {
    await Compte.assurerSession();
    return JSON.parse(localStorage.getItem("bizzoo-session") || "{}");
  });
  ok(apres.access_token === JETON && apres.tel === "22997000000",
    "un compte SMS garde son numéro après le rafraîchissement (" + (apres.tel || "vide") + ")");
  await ctx.close();
}
await nav.close();

/* ------------------------------------------------------------------ */
titre("7. Le .htaccess, sur un vrai Apache");
const APACHE = ["/usr/sbin/apache2", "/usr/sbin/httpd"].find((f) => fs.existsSync(f));
const MODULES = ["/usr/lib/apache2/modules", "/usr/lib64/httpd/modules", "/usr/lib/httpd/modules"]
  .find((d) => fs.existsSync(path.join(d, "mod_rewrite.so")));
if (!APACHE || !MODULES || !fs.existsSync(path.join(HEB, ".htaccess"))) {
  console.log("  sauté  Apache n'est pas installé ici (apt install apache2 pour éprouver le .htaccess)");
} else {
  const A = path.join(TMP, "apache");
  fs.mkdirSync(path.join(A, "run"), { recursive: true });
  execFileSync("openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", path.join(A, "cle.pem"),
    "-out", path.join(A, "cert.pem"), "-days", "1", "-subj", "/CN=www.bizzoomarket.com"], { stdio: "ignore" });
  /* Le serveur lit le site sous un autre utilisateur que le banc. */
  execFileSync("chmod", ["-R", "a+rX", TMP]);
  /* LES TYPES D'UN HÉBERGEUR AVARE : ni APK, ni woff2, ni manifeste. Le
     /etc/mime.types d'Ubuntu les connaît déjà — avec lui, le banc ne
     verrait pas un .htaccess qui aurait oublié de les apprendre au
     serveur. */
  fs.writeFileSync(path.join(A, "mime.types"), [
    "text/html html htm", "text/css css", "text/javascript js", "application/json json",
    "image/png png", "image/jpeg jpg jpeg", "image/svg+xml svg", "text/plain txt",
    "application/xml xml",
  ].join("\n") + "\n");
  const PH = 18000 + Math.floor(Math.random() * 1000);
  const PS = PH + 1000;
  const conf = [
    `ServerRoot "${A}"`, `DefaultRuntimeDir "${A}/run"`, `PidFile "${A}/run/httpd.pid"`,
    `ErrorLog "${A}/erreurs.log"`, "LogLevel warn", "ServerName www.bizzoomarket.com",
    `Listen 127.0.0.1:${PH}`, `Listen 127.0.0.1:${PS}`,
    ...(process.getuid && process.getuid() === 0 ? ["User nobody", "Group nogroup"] : []),
    ...["mpm_event", "authz_core", "dir", "mime", "rewrite", "headers", "filter", "deflate",
      "socache_shmcb", "ssl"].map((m) => `LoadModule ${m}_module ${MODULES}/mod_${m}.so`),
    `TypesConfig "${A}/mime.types"`, "DirectoryIndex index.html", "AccessFileName .htaccess",
    `DocumentRoot "${HEB}"`,
    "<Directory />", "  AllowOverride None", "  Require all denied", "</Directory>",
    /* CE QUE PERMETTENT LES HÉBERGEMENTS LES PLUS AVARES. Une directive
       qui en demande plus, et c'est l'erreur 500 partout. */
    `<Directory "${HEB}">`, "  AllowOverride FileInfo", "  Require all granted", "</Directory>",
    `<VirtualHost 127.0.0.1:${PS}>`, "  SSLEngine on",
    `  SSLCertificateFile "${A}/cert.pem"`, `  SSLCertificateKeyFile "${A}/cle.pem"`, "</VirtualHost>",
  ].join("\n");
  fs.writeFileSync(path.join(A, "httpd.conf"), conf);
  const serveur = spawn(APACHE, ["-f", path.join(A, "httpd.conf"), "-DFOREGROUND"], { stdio: "ignore" });

  const demander = (tls, hote, chemin, { methode = "HEAD", entetes = {} } = {}) => new Promise((ok_, ko) => {
    const req = (tls ? https : http).request({ host: "127.0.0.1", port: tls ? PS : PH, path: chemin,
      method: methode, servername: tls ? hote : undefined, rejectUnauthorized: false,
      headers: { Host: hote, ...entetes } }, (res) => {
      const morceaux = [];
      res.on("data", (c) => morceaux.push(c));
      res.on("end", () => ok_({ statut: res.statusCode, h: res.headers, corps: Buffer.concat(morceaux) }));
    });
    req.on("error", ko);
    req.end();
  });
  let pret = false;
  for (let i = 0; i < 40 && !pret; i++) {
    try { await demander(false, "www.bizzoomarket.com", "/"); pret = true; } catch (_) { await pause(150); }
  }
  ok(pret, "Apache démarre avec ce .htaccess");
  if (pret) {
    const www = "www.bizzoomarket.com";
    let r = await demander(false, www, "/");
    ok(r.statut === 301 && r.h.location === "https://www.bizzoomarket.com/", "http:// → https://");
    r = await demander(false, "bizzoomarket.com", "/client/");
    ok(r.statut === 301 && r.h.location === "https://www.bizzoomarket.com/client/",
      "bizzoomarket.com → www.bizzoomarket.com, en un seul saut");
    r = await demander(true, "bizzoomarket.com", "/");
    ok(r.statut === 301 && r.h.location === "https://www.bizzoomarket.com/", "même en https://");
    r = await demander(false, www, "/", { entetes: { "X-Forwarded-Proto": "https" } });
    ok(r.statut === 200, "derrière un relais HTTPS, pas de boucle de redirection");

    r = await demander(true, www, "/");
    ok(r.statut === 200, "https://www.bizzoomarket.com/ répond 200");
    ok(r.h["x-content-type-options"] === "nosniff" && r.h["x-frame-options"] === "SAMEORIGIN" &&
      r.h["referrer-policy"] === "strict-origin-when-cross-origin",
      "les en-têtes de sécurité sont posés");
    ok(/geolocation=\(self\)/.test(r.h["permissions-policy"] || "") &&
      /camera=\(\)/.test(r.h["permissions-policy"] || ""), "la position permise, la caméra non");
    ok(/max-age=15552000/.test(r.h["strict-transport-security"] || ""), "HTTPS obligatoire, six mois");
    ok(r.h["cache-control"] === "no-cache" && /charset=utf-8/i.test(r.h["content-type"] || ""),
      "la page se revalide à chaque visite, en UTF-8");
    r = await demander(true, www, "/client/sw.js");
    ok(r.h["cache-control"] === "no-cache", "le service worker aussi");
    r = await demander(true, www, "/apk/bizzoo-client.apk");
    ok(r.statut === 200 && r.h["content-type"] === "application/vnd.android.package-archive" &&
      /attachment/.test(r.h["content-disposition"] || ""), "l'APK part avec son type : Android propose de l'installer");
    r = await demander(true, www, "/client/polices/poppins-400.woff2");
    ok(r.h["content-type"] === "font/woff2" && /immutable/.test(r.h["cache-control"] || ""),
      "les polices se gardent un an");
    r = await demander(true, www, "/client/manifest.webmanifest");
    ok(/^application\/manifest\+json/.test(r.h["content-type"] || ""), "le manifeste a son type");
    r = await demander(true, www, "/vitrine/partage.jpg");
    ok(/max-age=604800/.test(r.h["cache-control"] || ""), "les images, une semaine");
    r = await demander(true, www, "/", { methode: "GET", entetes: { "Accept-Encoding": "gzip" } });
    ok(r.h["content-encoding"] === "gzip", "le texte part compressé");
    r = await demander(true, www, "/une/page/inconnue", { methode: "GET" });
    ok(r.statut === 404 && /Page introuvable/.test(r.corps.toString("utf8")), "une adresse inconnue : 404, avec la page de BIZZOO");
    r = await demander(true, www, "/README.md");
    ok(r.statut === 404, "le README n'est pas en ligne");
    const journal = fs.existsSync(path.join(A, "erreurs.log")) ? fs.readFileSync(path.join(A, "erreurs.log"), "utf8") : "";
    ok(!/not allowed here|Invalid command|\.htaccess:/.test(journal),
      "aucune directive refusée par « AllowOverride FileInfo »" +
      (/\.htaccess:/.test(journal) ? " : " + journal.split("\n").find((l) => /\.htaccess:/.test(l)) : ""));
  }
  serveur.kill("SIGTERM");
  await pause(300);
}

fs.rmSync(TMP, { recursive: true, force: true });
console.log(echecs ? "\n" + echecs + " constat(s) en échec.\n"
  : "\nLe site est prêt à partir en ligne ✔\n");
process.exit(echecs ? 1 : 0);
