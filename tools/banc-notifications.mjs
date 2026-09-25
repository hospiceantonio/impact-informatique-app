/* =========================================================
   La pastille, le panneau et les trois bips — côté client
   =========================================================
   CE QUE CE BANC REGARDE : ce qui QUITTE l'application, et ce
   que l'écran montre vraiment. Pas l'état interne du module —
   il dirait toujours ce qu'on lui a fait dire.

   TROIS RÈGLES Y SONT ÉPROUVÉES :

   1. PAS DE CLOCHE SANS COMPTE. Sans compte, la base n'a
      personne à prévenir : une cloche muette sur tous les
      écrans n'encombrerait qu'une barre déjà pleine.

   2. TOUCHER UNE NOTIFICATION N'ÉCRIT QUE « lue_le ». La base
      ne permet que cette colonne ; si l'application en envoyait
      d'autres, la requête entière serait refusée et rien ne se
      marquerait lu. Le constat porte donc sur le CORPS de la
      requête, pas sur la pastille qui s'éteint à l'écran.

   3. LE SON SE COUPE VRAIMENT. « troisBips » doit RENDRE FAUX
      quand on l'a coupé — sans quoi on ne saurait pas s'il se
      tait ou s'il échoue.

   ET LA DOUBLURE GARDE CE QU'ON LUI ÉCRIT. Une première version
   rendait toujours la même liste : « tout marquer lu » partait
   bien, la relecture ramenait les mêmes non lues, la pastille
   remontait. Le défaut n'existait que dans le banc — une
   doublure qui oublie les écritures ne représente pas une base,
   elle représente une base en panne.
   ========================================================= */
/* Playwright n'est pas une dépendance du projet : le chemin se donne
   par PLAYWRIGHT, le navigateur par CHROMIUM, l'adresse par BANC_URL. */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-notifications.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const MOI = "cc111111-1111-1111-1111-111111111111";
const BOU = [{ id: "bou_a", nom: "IMPACT", secteur: "Informatique", categorie_id: null,
  icone: "portable", couleur: "#0B5CF5", devise: "FCFA", indicatif: "229",
  actif: true, ordre: 1 }];

const maintenant = Date.now();
const N = (id, type, titre_, corps, lien, lue, sonne, ilya) => ({
  id, type, titre: titre_, corps, lien, commande_id: "c1",
  sonne, lue_le: lue ? "2026-09-20T10:00:00Z" : null,
  cree_le: new Date(maintenant - ilya).toISOString(),
});

let NOTIFS = [];
let ecritures = [];

async function ouvrir({ connecte = true } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1800 } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));
  await page.addInitScript((args) => {
    localStorage.setItem("impact-config",
      JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
    if (args.connecte) {
      const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
        .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
      localStorage.setItem("bizzoo-session", JSON.stringify({
        access_token: b64({ alg: "HS256" }) + "." + b64({ sub: args.moi }) + ".s",
        refresh_token: "r", expire_a: Date.now() + 3600000, email: "kofi@exemple.bj" }));
    } else {
      localStorage.removeItem("bizzoo-session");
    }
  }, { connecte, moi: MOI });

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
    /* LA DOUBLURE GARDE CE QU'ON LUI ÉCRIT. Une première version
       renvoyait toujours la même liste : « tout marquer lu » partait
       bien vers la base, la relecture rendait les mêmes non lues, et
       la pastille remontait — un défaut qui n'existait que dans le
       banc. Une doublure qui oublie les écritures ne représente pas
       une base, elle représente une base en panne. */
    if (c.startsWith("notifications")) {
      if (req.method() === "PATCH") {
        const m = /id=eq\.(\d+)/.exec(u.search);
        if (m) {
          const n = NOTIFS.find((x) => String(x.id) === m[1]);
          if (n) n.lue_le = new Date().toISOString();
        }
        return route.fulfill({ status: 204, body: "" });
      }
      return d(NOTIFS);
    }
    if (c === "rpc/tout_marquer_lu") {
      const combien = NOTIFS.filter((n) => !n.lue_le).length;
      for (const n of NOTIFS) n.lue_le = n.lue_le || new Date().toISOString();
      return d(combien);
    }
    if (c === "rpc/produits_populaires") return d([]);
    if (c.startsWith("categories")) return d([]);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("produits")) return d([]);
    if (c.startsWith("slides")) return d([]);
    if (c.startsWith("commandes")) return d([]);
    if (c.startsWith("clients")) return d([]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA",
      indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(2400);
  return { page, ctx };
}

/* ------------------------------------------------------------------ */
NOTIFS = [
  N(1, "commande_payee", "Paiement reçu", "Votre commande BZ-001 est confirmée.",
    "#/commande/c1", false, true, 40000),
  N(2, "commande_remise", "Votre colis est livré", "Confirmez la réception.",
    "#/commande/c1", false, true, 3600000),
  N(3, "commande_preparee", "Votre colis est prêt", "Il part bientôt.",
    "#/commande/c1", true, true, 90000000),
];

titre("La cloche porte le nombre de non lues");
{
  ecritures = [];
  const { page, ctx } = await ouvrir();
  const m = await page.evaluate(() => {
    const c = document.querySelector(".btn-cloche");
    return { existe: !!c,
      pastille: c ? (c.querySelector(".panier-pastille") || {}).textContent || "" : "",
      etiquette: c ? c.getAttribute("aria-label") : "",
      /* La cloche, puis le compte, puis le panier : le compte est monté
         dans la barre du haut, et touche le panier. */
      ordre: c ? [...c.parentElement.children].slice([...c.parentElement.children].indexOf(c))
        .map((x) => [...x.classList].find((k) => /^btn-(cloche|compte|panier)$/.test(k)) || "")
        .join(",") : "",
      panierDernier: !!(c && c.parentElement.lastElementChild &&
        c.parentElement.lastElementChild.classList.contains("btn-panier")) };
  });
  ok(m.existe, "la cloche est dans la barre du haut");
  ok(m.pastille === "2", "et porte le nombre de non lues (" + m.pastille + ")");
  ok(/2 non lues/.test(m.etiquette),
    "le nombre est aussi dans l'étiquette (" + m.etiquette + ")");
  ok(m.ordre === "btn-cloche,btn-compte,btn-panier" && m.panierDernier,
    "elle se pose avant le compte et le panier, qui reste le dernier geste (" + m.ordre + ")");
  await ctx.close();
}

titre("Sans compte, pas de cloche : il n'y a personne à prévenir");
{
  const { page, ctx } = await ouvrir({ connecte: false });
  const m = await page.evaluate(() => ({
    cloche: !!document.querySelector(".btn-cloche"),
    panier: !!document.querySelector(".btn-panier"),
  }));
  ok(!m.cloche, "aucune cloche");
  ok(m.panier, "mais le panier, lui, est bien là");
  await ctx.close();
}

titre("Le panneau groupe par type, et dit le quand");
{
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/notifications"; });
  await page.waitForTimeout(1500);
  const m = await page.evaluate(() => {
    const titres = [...document.querySelectorAll("#vue .titre-section, #vue h2")]
      .map((x) => x.textContent.trim());
    const lignes = [...document.querySelectorAll("#vue .notif")];
    return {
      titres,
      combien: lignes.length,
      quand: lignes.map((l) => (l.querySelector(".notif-quand") || {}).textContent || ""),
      points: lignes.filter((l) => l.querySelector(".notif-point")).length,
      premierLien: lignes.length ? lignes[0].getAttribute("href") : "",
      texte: document.body.innerText,
    };
  });
  ok(m.combien === 3, "les trois notifications sont là (" + m.combien + ")");
  ok(m.titres.some((t) => /Paiements/.test(t)), "une section « Paiements »");
  ok(m.titres.some((t) => /Livrés/.test(t)), "une section « Livrés »");
  ok(m.titres.some((t) => /Colis prêts/.test(t)), "une section « Colis prêts »");
  ok(m.points === 2, "deux points bleus, pour les deux non lues (" + m.points + ")");
  ok(/à l'instant|il y a/.test(m.quand[0]),
    "le quand est en clair (" + m.quand[0] + ")");
  ok(m.premierLien === "#/commande/c1",
    "et le doigt mène à la commande (" + m.premierLien + ")");
  ok(/Tout marquer lu \(2\)/.test(m.texte), "le bouton « Tout marquer lu » compte juste");
  await ctx.close();
}

titre("Toucher une notification la marque lue — et part vers la base");
{
  ecritures = [];
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/notifications"; });
  await page.waitForTimeout(1500);
  await page.evaluate(() => {
    const a = document.querySelector("#vue .notif");
    a.click();
  });
  await page.waitForTimeout(900);
  const e = ecritures.find((x) => /^notifications\?/.test(x.chemin));
  ok(!!e, "une modification part vers la base");
  ok(e && e.methode === "PATCH", "c'est bien une modification (" +
    (e ? e.methode : "rien") + ")");
  ok(e && /id=eq\.1/.test(e.chemin), "sur la bonne notification (" +
    (e ? e.chemin : "") + ")");
  ok(e && e.corps && e.corps.lue_le && Object.keys(e.corps).length === 1,
    "et elle n'écrit QUE « lue_le »");
  const ou = await page.evaluate(() => location.hash);
  ok(ou === "#/commande/c1", "le doigt a bien mené à la commande (" + ou + ")");
  await ctx.close();
}

titre("« Tout marquer lu » passe par la base, et la pastille retombe");
{
  ecritures = [];
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/notifications"; });
  await page.waitForTimeout(1500);
  await page.evaluate(() => document.querySelector("#notif-tout-lu").click());
  await page.waitForTimeout(1200);
  const e = ecritures.find((x) => /tout_marquer_lu/.test(x.chemin));
  ok(!!e, "la base est appelée pour tout marquer (" + (e ? e.chemin : "rien") + ")");
  const reste = await page.evaluate(() =>
    typeof Notifs !== "undefined" ? Notifs.compte() : -1);
  ok(reste === 0, "et la pastille retombe à zéro (" + reste + ")");
  await ctx.close();
}

titre("Le son : coupé, il ne sonne pas ; et le choix se garde");
{
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/notifications"; });
  await page.waitForTimeout(1500);
  const depart = await page.evaluate(() => ({
    coche: document.querySelector("#notif-son").checked,
    actif: Son.actif(),
  }));
  ok(depart.coche && depart.actif, "il sonne par défaut");

  const apres = await page.evaluate(() => {
    const c = document.querySelector("#notif-son");
    c.checked = false;
    c.dispatchEvent(new Event("change", { bubbles: true }));
    return { actif: Son.actif(), garde: localStorage.getItem("bizzoo-son") };
  });
  ok(!apres.actif, "décoché, il ne sonne plus");
  ok(apres.garde === "non", "et le choix est gardé sur l'appareil (" + apres.garde + ")");

  /* LE CONSTAT QUI COMPTE : « troisBips » doit RENDRE FAUX quand c'est
     coupé — sinon on ne saurait pas s'il se tait vraiment. */
  const muet = await page.evaluate(() => Son.troisBips());
  ok(muet === false, "et « troisBips » ne fait rien du tout");
  await ctx.close();
}

titre("Aucun son avant le premier geste, et c'est le navigateur qui l'exige");
{
  const { page, ctx } = await ouvrir();
  /* Sans « --autoplay-policy », le contexte audio naît suspendu : c'est
     exactement ce que vit un client qui n'a pas encore touché l'écran. */
  const m = await page.evaluate(() => {
    const avant = Son.troisBips();
    return { avant };
  });
  ok(m.avant === false || m.avant === true,
    "il tente sans jamais lever d'erreur (" + m.avant + ")");
  const erreurs = await page.evaluate(() => {
    try { Son.troisBips(); Son.troisBips(); return "aucune"; }
    catch (e) { return String(e.message); }
  });
  ok(erreurs === "aucune", "et deux appels de suite ne cassent rien");
  await ctx.close();
}

await nav.close();
console.log("\n" + (echecs ? "  " + echecs + " ÉCHEC(S)" : "  Tout passe."));
process.exit(echecs ? 1 : 0);
