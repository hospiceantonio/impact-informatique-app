/* =========================================================
   Le pixel Meta : dix événements, au bon moment, une seule fois
   =========================================================
   CE QU'ON DÉFEND ICI. La publicité de BIZZOO apprend du site ce
   qui s'y passe : pages vues, produits consultés, ajouts au panier,
   commandes, paiements, inscriptions, recherches, contacts. Un
   événement en trop fausse les chiffres qu'on paie ; un événement
   au mauvais moment — l'achat compté au clic sur « Payer » —
   fait optimiser les publicités sur des ventes qui n'existent pas.

   LE SITE EST SERVI SOUS SA VRAIE ADRESSE, www.bizzoomarket.com :
   le pixel ne se charge que là. Le script de Meta est remplacé par
   un enregistreur, et chaque appel à « fbq » est noté AU MOMENT où
   il part, avec l'adresse de la page — c'est elle que Meta reçoit.
   Rien ne quitte la machine.

   CE QUI EST ÉPROUVÉ :
     1. ni l'application Android, ni la copie de GitHub Pages ne
        chargent le pixel ;
     2. la vitrine : une page vue, la configuration automatique
        coupée, le suivi automatique des adresses interdit ;
     3. une page vue par écran — pas pour un écran redessiné, pas
        pour un écran qui renvoie aussitôt ailleurs ;
     4. le produit consulté, et l'ajout au panier de ce qui est
        vraiment entré ;
     5. la commande lancée, le moyen de paiement une seule fois, et
        l'ACHAT SEULEMENT QUAND LA BASE CONFIRME — une seule fois,
        même si le reçu se rouvre ;
     6. l'inscription par e-mail, par numéro (la naissance du compte,
        pas chaque retour), et la demande de compte revendeur ;
     7. la recherche quand on a fini de taper, sans numéro ni e-mail ;
     8. le contact par WhatsApp, téléphone, e-mail — pas le partage ;
     9. aucun nom, numéro ou e-mail dans ce qui part, et jamais de
        jeton dans l'adresse que Meta reçoit.

   Lancer :
     PLAYWRIGHT=<chemin>/playwright-core/index.js \
     CHROMIUM=<chemin>/chrome node tools/banc-pixel-meta.mjs
   ========================================================= */
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-pixel-meta.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const RACINE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SITE = "https://www.bizzoomarket.com";
const ID = "1786119222612781";

let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

/* ---------- Le catalogue d'essai ---------- */

const BOUTIQUE = { id: "bou_info", nom: "IMPACT", secteur: "Informatique", categorie_id: null,
  icone: "portable", couleur: "#0B5CF5", devise: "FCFA", indicatif: "229", actif: true, ordre: 1,
  description: "", adresse: "Cotonou", tel: "0197000000", whatsapp: "0197000000", horaires: "",
  photos: [], telephones: [], adresses: [] };
const CATEGORIES = [{ id: "cat_ht", nom: "High-tech", icone: "portable", couleur: "#0047D9",
  image: "", en_avant: true, ordre: 1,
  sous_categories: [{ id: "sc_acc", categorie_id: "cat_ht", nom: "Accessoires", ordre: 1 }] }];
const produit = (id, code, nom, prix, stock) => ({ id, code, nom, reference: "", description: "",
  prix, ancien_prix: null, categorie_id: "cat_ht", sous_categorie_id: "sc_acc", stock,
  disponible: stock > 0, sur_commande: false, appro_le: null, images: [], video: "",
  boutique_id: "bou_info", en_avant: false, ordre_avant: 0, flash_fin: null,
  cree_le: "2026-10-01T10:00:00Z", modifie_le: "2026-10-01T10:00:00Z" });
const PRODUITS = [
  produit("prod_a", "100201", "Ordinateur portable", 18500, 10),
  produit("prod_b", "100202", "Souris sans fil", 4000, 10),
  produit("prod_c", "100203", "Clé USB", 2500, 1),
];

/* Ce qu'un client donne de lui-même : RIEN de cela ne doit partir. */
const CLIENT = { nom: "Awa Kossi", email: "awa.kossi@exemple.bj", tel: "0196000001",
  adresse: "Akpakpa, face au marché", commerce: "Quincaillerie Awa et fils" };
const PERSONNEL = [CLIENT.nom, CLIENT.email, CLIENT.tel, "96000001", "2290196000001",
  CLIENT.adresse, CLIENT.commerce, "0195000002", "95000002"];

/* ---------- Servir le site sous ses adresses ---------- */

const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".json": "application/json", ".png": "image/png",
  ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".svg": "image/svg+xml", ".webp": "image/webp",
  ".woff2": "font/woff2", ".webmanifest": "application/manifest+json", ".ico": "image/x-icon" };

async function servir(route, relatif) {
  let chemin = decodeURIComponent(relatif);
  if (!chemin || chemin.endsWith("/")) chemin += "index.html";
  const fichier = path.join(RACINE, chemin);
  if (!fichier.startsWith(RACINE)) return route.fulfill({ status: 403, body: "" });
  try {
    const corps = await readFile(fichier);
    return route.fulfill({ status: 200, body: corps,
      contentType: TYPES[path.extname(fichier).toLowerCase()] || "application/octet-stream" });
  } catch (_) {
    return route.fulfill({ status: 404, body: "introuvable" });
  }
}

/* ---------- Une base de données d'essai ---------- */

const jeton = (sub) => {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return b64({ alg: "HS256" }) + "." +
    b64({ sub, exp: Math.floor(Date.now() / 1000) + 3600, session_id: "s-" + sub }) + ".sig";
};
const session = (user) => ({ access_token: jeton(user.id), refresh_token: "r-" + user.id,
  expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, token_type: "bearer", user });

function nouvelEtat() {
  return {
    commandes: [],          // ce que « creer_commande » a reçu
    suivre: [],             // les états successifs que la base répondra
    signupConfirmation: false,
    verifyUser: null,       // l'utilisateur que « /verify » rendra
    fiche: null,            // la fiche client du compte connecté
    demandes: 0,            // les demandes de compte revendeur enregistrées
    commande: null,         // la commande que « creer_commande » rendra
    smsOuvert: true,        // le fournisseur « Phone » de Supabase
    lent: 0,                // une base qui met ce temps à rendre les commandes
  };
}

/* ---------- Ouvrir une page ----------
   Chaque appel à « fbq » passe par un enregistreur posé AVANT tout
   script de la page : un Proxy sur la fonction, qui note les
   arguments et l'adresse du moment, puis laisse l'appel se faire. Le
   journal vit côté banc : il survit aux changements de page. */

async function ouvrir({ adresse, etat = nouvelEtat(), avant = null, viewport = { width: 390, height: 900 } }) {
  const ctx = await nav.newContext({ viewport, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const journal = [];
  const reseau = { fbevents: 0, beacons: 0 };
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.exposeBinding("__noterPixel", (_source, entree) => { journal.push(entree); });
  await page.addInitScript((avant) => {
    let reel;
    Object.defineProperty(window, "fbq", {
      configurable: true,
      get() { return reel; },
      set(v) {
        reel = typeof v !== "function" ? v : new Proxy(v, {
          apply(cible, ceci, args) {
            try {
              const entree = { args: JSON.parse(JSON.stringify(args)), url: location.href };
              window.__noterPixel(entree);
              /* Aussi dans la mémoire de l'onglet, SUR-LE-CHAMP : une page
                 qui s'en va aussitôt — la vitrine qui passe la main à la
                 boutique — n'a pas le temps de prévenir le banc. */
              const l = JSON.parse(sessionStorage.getItem("banc-pixel") || "[]");
              l.push(entree);
              sessionStorage.setItem("banc-pixel", JSON.stringify(l));
            } catch (_) { /* rien */ }
            return Reflect.apply(cible, ceci, args);
          },
        });
      },
    });
    try {
      localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
      localStorage.removeItem("impact-boutique");
      if (avant && !sessionStorage.getItem("banc-pose")) {
        sessionStorage.setItem("banc-pose", "1");
        for (const [cle, valeur] of Object.entries(avant)) localStorage.setItem(cle, valeur);
      }
    } catch (_) { /* page sans stockage */ }
  }, avant);

  await ctx.route("https://connect.facebook.net/**", (r) => {
    reseau.fbevents++;
    return r.fulfill({ status: 200, contentType: "text/javascript",
      body: "window.__fbeventsCharge = (window.__fbeventsCharge || 0) + 1;" });
  });
  await ctx.route(/^https:\/\/([a-z]+\.)?facebook\.com\//, (r) => {
    reseau.beacons++;
    return r.fulfill({ status: 204, body: "" });
  });
  await ctx.route(SITE + "/**", (r) => servir(r, new URL(r.request().url()).pathname.slice(1)));
  await ctx.route("https://bizzoomarket.com/**", (r) =>
    servir(r, new URL(r.request().url()).pathname.slice(1)));
  await ctx.route("https://hospiceantonio.github.io/**", (r) =>
    servir(r, new URL(r.request().url()).pathname.replace(/^\/impact-informatique-app\//, "")));
  await ctx.route("https://appassets.androidx.dev/**", (r) =>
    servir(r, new URL(r.request().url()).pathname.replace(/^\/assets\/www\//, "client/")));
  await ctx.route("https://wa.me/**", (r) => r.fulfill({ status: 200, body: "" }));

  await ctx.route("https://base-absente.invalid/**", async (r) => {
    const req = r.request();
    const url = new URL(req.url());
    const d = (x, status = 200) => r.fulfill({ status, contentType: "application/json", body: JSON.stringify(x) });
    let corps = null;
    try { corps = req.postDataJSON(); } catch (_) { /* pas du JSON */ }

    if (url.pathname.startsWith("/auth/v1/")) {
      const a = url.pathname.slice("/auth/v1/".length);
      if (a === "settings") return d({ external: { email: true, phone: etat.smsOuvert } });
      if (a === "signup") {
        const user = { id: "u-email-" + (etat.commandes.length + Date.now()), email: corps && corps.email,
          created_at: new Date().toISOString(), last_sign_in_at: new Date().toISOString(),
          user_metadata: (corps && corps.data) || {} };
        return d(etat.signupConfirmation ? user : session(user));
      }
      if (a === "otp") return d({});
      if (a === "verify") return etat.verifyUser ? d(session(etat.verifyUser)) : d({ msg: "Token has expired" }, 403);
      if (a.startsWith("token")) return d(session({ id: "u-retour", email: CLIENT.email }));
      if (a === "user") return d({ id: "u-retour" });
      return d({});
    }
    if (url.pathname.startsWith("/functions/v1/")) return d({ ok: true, statut: "en_attente" });

    const c = url.pathname.replace(/^\/rest\/v1\//, "");
    const methode = req.method();
    if (c.startsWith("rpc/creer_commande")) {
      etat.commandes.push(corps);
      return d(etat.commande);
    }
    if (c.startsWith("rpc/suivre_commande")) {
      const prochain = etat.suivre.length > 1 ? etat.suivre.shift() : etat.suivre[0];
      return d(prochain || { etat: "a_payer" });
    }
    if (c.startsWith("rpc/rattacher_mes_commandes")) return d(0);
    if (c.startsWith("commandes")) {
      if (etat.lent) await pause(etat.lent);
      return d([]);
    }
    if (c.startsWith("rpc/")) return d([]);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: true, fournisseur: "feexpay",
      cle_publique: "", bac_a_sable: false, taux_acompte: 10 }]);
    if (c.startsWith("produits")) return d(PRODUITS);
    if (c.startsWith("categories")) return d(CATEGORIES);
    if (c.startsWith("boutiques")) return d([BOUTIQUE]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229",
      whatsapp: "0142323238" }]);
    if (c.startsWith("clients")) {
      if (methode === "PATCH" && etat.fiche) {
        Object.assign(etat.fiche, corps || {});
        if (corps && corps.type_compte === "revendeur") {
          etat.demandes++;
          etat.fiche.revendeur_etat = "en_attente";
        }
        return d([etat.fiche]);
      }
      if (methode === "POST") return d([etat.fiche || corps || {}]);
      return d(etat.fiche ? [etat.fiche] : []);
    }
    return d([]);
  });

  await page.goto(adresse, { waitUntil: "domcontentloaded" });
  await pause(1500);
  /* Les liens de contact ne quittent pas la page pendant l'essai : le
     pixel les entend AVANT (phase de capture), puis on les retient. */
  await page.evaluate(() => {
    document.addEventListener("click", (ev) => {
      const a = ev.target.closest && ev.target.closest("a[href]");
      if (a && /^(https:\/\/wa\.me|tel:|mailto:)/.test(a.getAttribute("href") || "")) ev.preventDefault();
    });
  }).catch(() => {});
  return { ctx, page, journal, reseau, erreurs, etat };
}

const traces = (journal, nom) =>
  journal.filter((e) => e.args[0] === "track" && (!nom || e.args[1] === nom));
const donnees = (journal, nom) => traces(journal, nom).map((e) => e.args[2] || {});
const aller = async (page, hash, attente = 1300) => {
  await page.evaluate((h) => { location.hash = h; }, hash);
  await pause(attente);
};
const tousLesJournaux = [];

/* =====================================================
   1. Ni l'application Android, ni GitHub Pages
   ===================================================== */

titre("1. Le pixel ne vit que sur l'adresse officielle");
{
  for (const [nom, adresse] of [
    ["l'application Android (appassets.androidx.dev)", "https://appassets.androidx.dev/assets/www/index.html"],
    ["la boutique sur GitHub Pages", "https://hospiceantonio.github.io/impact-informatique-app/client/index.html"],
    ["la vitrine sur GitHub Pages", "https://hospiceantonio.github.io/impact-informatique-app/"],
  ]) {
    const o = await ouvrir({ adresse: nom.includes("boutique") || nom.includes("Android")
      ? adresse + "#/produit/prod_a" : adresse });
    await pause(400);
    const fbq = await o.page.evaluate(() => typeof window.fbq);
    ok(o.reseau.fbevents === 0 && !o.journal.length && fbq === "undefined",
      nom + " : aucun pixel (" + o.reseau.fbevents + " script, " + o.journal.length + " appel)");
    await o.ctx.close();
  }
}

/* =====================================================
   2. La vitrine
   ===================================================== */

titre("2. La vitrine compte une page vue, et rien d'autre");
{
  const o = await ouvrir({ adresse: SITE + "/" });
  await pause(300);
  const j = o.journal;
  const iAuto = j.findIndex((e) => e.args[0] === "set" && e.args[1] === "autoConfig");
  const iInit = j.findIndex((e) => e.args[0] === "init");
  ok(iAuto >= 0 && j[iAuto].args[2] === false && j[iAuto].args[3] === ID,
    "la configuration automatique de Meta est coupée");
  ok(iInit > iAuto && j[iInit].args[1] === ID, "AVANT l'initialisation du pixel " + ID);
  ok(traces(j, "PageView").length === 1 && traces(j).length === 1,
    "une page vue, et aucun autre événement (" + traces(j).map((e) => e.args[1]).join(", ") + ")");
  ok(await o.page.evaluate(() => window.fbq && window.fbq.disablePushState === true),
    "Meta n'a pas le droit de compter tout seul les changements d'adresse");
  ok(o.reseau.fbevents === 1, "le script de Meta est demandé une fois (" + o.reseau.fbevents + ")");
  await o.page.evaluate(() => { location.hash = "#i-telecharger"; });
  await pause(400);
  ok(traces(o.journal, "PageView").length === 1, "une ancre de la vitrine n'est pas une page vue");
  ok(!o.erreurs.length, "aucune erreur dans la page" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  tousLesJournaux.push(...o.journal);
  await o.ctx.close();
}

/* =====================================================
   3. Une page vue par écran
   ===================================================== */

titre("3. Une page vue par écran, et pas une de plus");
{
  const o = await ouvrir({ adresse: SITE + "/client/index.html" });
  const vues = () => traces(o.journal, "PageView");
  ok(vues().length === 1, "l'accueil : une page vue (" + vues().length + ")");
  ok(o.journal.filter((e) => e.args[0] === "init").length === 1, "un seul « init »");
  {
    const j = o.journal;
    const iAuto = j.findIndex((e) => e.args[0] === "set" && e.args[1] === "autoConfig" && e.args[2] === false);
    const iInit = j.findIndex((e) => e.args[0] === "init");
    ok(iAuto >= 0 && iAuto < iInit, "la boutique aussi coupe la configuration automatique, avant « init »");
    ok(await o.page.evaluate(() => window.fbq && window.fbq.disablePushState === true),
      "et interdit à Meta de compter tout seul ses changements d'écran");
  }

  await aller(o.page, "#/categories");
  ok(vues().length === 2 && /#\/categories$/.test(vues()[1].url),
    "les catégories : une de plus, à leur adresse (" + (vues()[1] || {}).url + ")");

  await aller(o.page, "#/produit/prod_a");
  ok(vues().length === 3, "la fiche produit : une de plus (" + vues().length + ")");

  /* Le catalogue se met à jour pendant qu'on lit : l'écran se
     redessine, mais personne n'a navigué. */
  await o.page.evaluate(() => document.dispatchEvent(new Event("catalogue:maj")));
  /* Au-delà des deux secondes après lesquelles un écran compte de toute
     façon : un écran redessiné pris pour une visite aurait eu le temps
     de se déclarer. */
  await pause(2600);
  ok(vues().length === 3 && traces(o.journal, "ViewContent").length === 1,
    "un écran redessiné n'ajoute ni page vue ni produit consulté");

  await aller(o.page, "#/inconnu");
  ok(vues().length === 4 && /#\/$/.test(vues()[3].url),
    "une adresse inconnue renvoie à l'accueil : UNE page vue, celle de l'accueil (" +
    vues().slice(3).map((v) => v.url.replace(SITE, "")).join(", ") + ")");

  await aller(o.page, "#/commande");
  ok(vues().length === 5 && /#\/panier$/.test(vues()[4].url),
    "« commande » avec un panier vide renvoie au panier : seule la page du panier compte (" +
    vues().slice(4).map((v) => v.url.replace(SITE, "")).join(", ") + ")");
  ok(o.reseau.beacons === 0, "rien n'est parti vers facebook.com");
  ok(!o.erreurs.length, "aucune erreur dans la page" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  tousLesJournaux.push(...o.journal);
  await o.ctx.close();
}

titre("3 bis. Un écran lent compte au bout de deux secondes");
{
  /* La commande d'un autre téléphone : le reçu la demande à la base, qui
     met quatre secondes à répondre. L'écran « Lecture de la commande… »
     est pourtant sous les yeux du client — il compte sans attendre. */
  const etat = nouvelEtat();
  etat.lent = 4000;
  etat.fiche = { id: "u-client", nom: CLIENT.nom, tel: CLIENT.tel, indicatif: "229", tel_verifie: true,
    type_compte: "client", revendeur_etat: "aucune" };
  const o = await ouvrir({ adresse: SITE + "/client/index.html#/", etat,
    avant: { "bizzoo-session": JSON.stringify({ access_token: jeton("u-client"), refresh_token: "r",
      expire_a: Date.now() + 3600000, email: CLIENT.email, tel: "2290196000001" }) } });
  await aller(o.page, "#/commande/cmd_ailleurs", 2600);
  ok(traces(o.journal, "PageView").some((e) => /#\/commande\/cmd_ailleurs$/.test(e.url)),
    "la commande lue au loin : sa page vue part avant la réponse de la base");
  await pause(2500);
  ok(traces(o.journal, "PageView").filter((e) => /#\/commande\/cmd_ailleurs$/.test(e.url)).length === 1,
    "et la réponse, arrivée ensuite, ne la redit pas");
  tousLesJournaux.push(...o.journal);
  await o.ctx.close();
}

/* =====================================================
   4. Le produit consulté, l'ajout au panier
   ===================================================== */

titre("4. Le produit consulté, puis ce qui entre vraiment au panier");
{
  const o = await ouvrir({ adresse: SITE + "/client/index.html#/produit/prod_a" });
  const vu = donnees(o.journal, "ViewContent");
  ok(vu.length === 1, "la fiche ouverte : un produit consulté (" + vu.length + ")");
  const v = vu[0] || {};
  ok(JSON.stringify(v.content_ids) === '["prod_a"]' && v.content_type === "product" &&
     v.content_name === "Ordinateur portable",
    "son identifiant, son nom, « product » (" + JSON.stringify(v) + ")");
  ok(v.value === 18500 && v.currency === "XOF", "le prix en nombre simple, en XOF (" + v.value + " " + v.currency + ")");
  const ordre = traces(o.journal).map((e) => e.args[1]);
  ok(ordre.indexOf("PageView") >= 0 && ordre.indexOf("PageView") < ordre.indexOf("ViewContent"),
    "la page vue arrive avant le produit consulté (" + ordre.join(" → ") + ")");

  await o.page.click("#p-plus");
  await o.page.click("#p-ajouter");
  await pause(300);
  const ajout = donnees(o.journal, "AddToCart");
  ok(ajout.length === 1, "« Ajouter au panier » : un ajout (" + ajout.length + ")");
  const a = ajout[0] || {};
  ok(JSON.stringify(a.content_ids) === '["prod_a"]' && a.num_items === 2 &&
     a.value === 37000 && a.currency === "XOF",
    "deux pièces à 18 500 : 37000 XOF (" + JSON.stringify(a) + ")");

  await aller(o.page, "#/produit/prod_c");
  await o.page.click("#p-ajouter");
  await pause(300);
  await o.page.click("#p-ajouter");
  await pause(300);
  const c = donnees(o.journal, "AddToCart").filter((x) => x.content_ids[0] === "prod_c");
  ok(c.length === 1 && c[0].num_items === 1,
    "la dernière clé USB entre une fois ; le second clic n'ajoute rien, et rien ne part (" + c.length + ")");
  ok(!o.erreurs.length, "aucune erreur dans la page" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  tousLesJournaux.push(...o.journal);
  await o.ctx.close();
}

/* =====================================================
   5. Commander, payer, et l'achat confirmé par la base
   ===================================================== */

titre("5. L'achat ne compte qu'une fois la base l'ayant confirmé");
{
  const etat = nouvelEtat();
  etat.commande = { id: "cmd_1", numero: "BZ-000123", total: 41000, devise: "FCFA", etat: "a_payer",
    code_promo: null, remise: 0, acompte: 4100, taux_acompte: 10,
    boutiques: [{ id: "bou_info", nom: "IMPACT", whatsapp: "0197000000", indicatif: "229", montant: 41000,
      lignes: [
        { nom: "Ordinateur portable", code: "100201", reference: "", prix: 18500, produit_id: "prod_a", quantite: 2 },
        { nom: "Souris sans fil", code: "100202", reference: "", prix: 4000, produit_id: "prod_b", quantite: 1 },
      ] }] };
  etat.suivre = [{ etat: "a_payer" }, { etat: "payee" }];
  const o = await ouvrir({ adresse: SITE + "/client/index.html#/panier", etat,
    avant: { "bizzoo-panier": JSON.stringify([
      { produitId: "prod_a", quantite: 2 }, { produitId: "prod_b", quantite: 1 }]) } });

  await o.page.click("#pa-commander");
  await pause(1500);
  const debut = donnees(o.journal, "InitiateCheckout");
  ok(debut.length === 1, "« Passer la commande » : une commande lancée (" + debut.length + ")");
  const d = debut[0] || {};
  ok(JSON.stringify(d.content_ids) === '["prod_a","prod_b"]' && d.num_items === 3 &&
     d.value === 41000 && d.currency === "XOF",
    "le panier entier : deux produits, trois pièces, 41000 XOF (" + JSON.stringify(d) + ")");

  await o.page.click('#co-operateurs [data-reseau="MTN"]');
  await o.page.click('#co-operateurs [data-reseau="MOOV"]');
  await pause(300);
  let infos = donnees(o.journal, "AddPaymentInfo");
  ok(infos.length === 1 && infos[0].payment_method === "MTN" && infos[0].value === 41000,
    "le moyen de paiement choisi part une fois, au premier choix (" + JSON.stringify(infos) + ")");

  await o.page.fill("#co-nom", CLIENT.nom);
  await o.page.fill("#co-tel", CLIENT.tel);
  await o.page.fill("#co-adresse", CLIENT.adresse);
  await o.page.fill("#co-mm-tel", "0195000002");
  await o.page.click("#co-payer");
  await pause(1500);
  infos = donnees(o.journal, "AddPaymentInfo");
  ok(infos.length === 1, "« Payer » ne le redit pas (" + infos.length + ")");
  ok(etat.commandes.length === 1, "la commande est créée");
  ok(donnees(o.journal, "Purchase").length === 0,
    "« Payer » n'est PAS un achat : rien tant que la base n'a pas confirmé");

  /* Le reçu patiente pour le paiement : il ne rend la main qu'après la
     confirmation. Il est pourtant sous les yeux du client — sa page vue
     part sans l'attendre. */
  await pause(1500);
  ok(traces(o.journal, "PageView").some((e) => /#\/commande\/cmd_1$/.test(e.url)) &&
     traces(o.journal, "Purchase").length === 0,
    "le reçu qui attend le versement compte comme une page vue, avant la confirmation");

  await pause(5500);
  const achats = traces(o.journal, "Purchase");
  ok(achats.length === 1, "la base confirme : UN achat (" + achats.length + ")");
  const p = (achats[0] || { args: [] }).args[2] || {};
  ok(p.value === 41000 && p.currency === "XOF" && Number.isInteger(p.value),
    "la valeur de la commande, en nombre simple, en XOF (" + p.value + " " + p.currency + ")");
  ok(p.acompte === 4100,
    "et, à côté, l'acompte versé en ligne — le reste se paie à la livraison (" + p.acompte + ")");
  ok(JSON.stringify(p.content_ids) === '["prod_a","prod_b"]' && p.num_items === 3 &&
     p.content_type === "product", "les produits et les quantités de la commande (" + JSON.stringify(p) + ")");
  ok(p.order_id === "BZ-000123", "le numéro de commande (" + p.order_id + ")");
  ok(((achats[0] || { args: [] }).args[3] || {}).eventID === "achat-BZ-000123",
    "et un identifiant d'événement, pour que Meta ne le compte jamais deux fois");

  await aller(o.page, "#/");
  await aller(o.page, "#/commande/cmd_1", 2500);
  ok(traces(o.journal, "Purchase").length === 1, "le reçu rouvert ne recompte pas l'achat");

  /* Le téléphone a perdu l'état « payée » — fermé trop tôt, stockage
     abîmé : il relit la base et la voit confirmer une seconde fois. La
     mémoire du pixel, elle, se souvient. */
  await o.page.evaluate(() => {
    const l = JSON.parse(localStorage.getItem("bizzoo-commandes") || "[]");
    for (const c of l) if (c.id === "cmd_1") c.etat = "a_payer";
    localStorage.setItem("bizzoo-commandes", JSON.stringify(l));
  });
  etat.suivre = [{ etat: "payee" }];
  await aller(o.page, "#/");
  await aller(o.page, "#/commande/cmd_1", 4500);
  ok(traces(o.journal, "Purchase").length === 1, "une confirmation relue ne fait pas un second achat");

  /* Une commande d'il y a dix jours, restée « à payer » sur ce téléphone :
     sa confirmation, relue aujourd'hui, n'est pas un achat du jour. */
  await o.page.evaluate(() => {
    const l = JSON.parse(localStorage.getItem("bizzoo-commandes") || "[]");
    l.unshift({ id: "cmd_vieille", numero: "BZ-000099", total: 4000, devise: "FCFA", etat: "a_payer",
      client: { nom: "", tel: "", indicatif: "229", adresse: "" },
      boutiques: [{ id: "bou_info", montant: 4000, lignes: [{ produit_id: "prod_b", quantite: 1, prix: 4000 }] }],
      gardeeLe: Date.now() - 10 * 864e5 });
    localStorage.setItem("bizzoo-commandes", JSON.stringify(l));
  });
  etat.suivre = [{ etat: "payee" }];
  await aller(o.page, "#/commande/cmd_vieille", 4500);
  const vieille = await o.page.evaluate(() =>
    (JSON.parse(localStorage.getItem("bizzoo-commandes") || "[]").find((c) => c.id === "cmd_vieille") || {}).etat);
  ok(vieille === "payee" && traces(o.journal, "Purchase").length === 1,
    "une commande d'il y a dix jours, confirmée aujourd'hui, n'est pas comptée comme un achat du jour (" +
    vieille + ")");
  ok(!o.erreurs.length, "aucune erreur dans la page" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  tousLesJournaux.push(...o.journal);
  await o.ctx.close();
}

titre("5 bis. Un paiement qui n'aboutit pas n'est pas un achat");
{
  const etat = nouvelEtat();
  etat.commande = { id: "cmd_2", numero: "BZ-000124", total: 4000, devise: "FCFA", etat: "a_payer",
    boutiques: [{ id: "bou_info", montant: 4000, lignes: [
      { nom: "Souris sans fil", prix: 4000, produit_id: "prod_b", quantite: 1 }] }] };
  etat.suivre = [{ etat: "echouee" }];
  const o = await ouvrir({ adresse: SITE + "/client/index.html#/commande", etat,
    avant: { "bizzoo-panier": JSON.stringify([{ produitId: "prod_b", quantite: 1 }]) } });
  await o.page.fill("#co-nom", CLIENT.nom);
  await o.page.fill("#co-tel", CLIENT.tel);
  await o.page.fill("#co-adresse", CLIENT.adresse);
  await o.page.fill("#co-mm-tel", "0195000002");
  if (!(await o.page.$("#co-operateurs .pay-methode.active"))) {
    await o.page.click('#co-operateurs [data-reseau="MOOV"]');
  }
  await o.page.click("#co-payer");
  await pause(5000);
  ok(donnees(o.journal, "AddPaymentInfo").length === 1, "le moyen de paiement est parti");
  ok(traces(o.journal, "Purchase").length === 0, "le versement refusé : aucun achat");
  tousLesJournaux.push(...o.journal);
  await o.ctx.close();
}

/* =====================================================
   6. Les comptes
   ===================================================== */

titre("6. L'inscription, et la demande de compte revendeur");
/* PAR LE NUMÉRO, la porte de la 3.58.0 : le nom, le numéro, le code. Le
   compte naît au code validé ; un revendeur dépose sa demande juste après. */
for (const [quoi, revendeur] of [["par son numéro, un client", false], ["par son numéro, un revendeur", true]]) {
  const etat = nouvelEtat();
  etat.verifyUser = { id: "u-tel-" + (revendeur ? "rv" : "cl"), phone: "2290196000001",
    created_at: new Date(Date.now() - 20000).toISOString(), last_sign_in_at: new Date().toISOString() };
  const o = await ouvrir({ adresse: SITE + "/client/index.html#/inscription", etat });
  if (revendeur) {
    await o.page.click('[data-type="revendeur"]');
    await o.page.fill("#cp-message", CLIENT.commerce);
  }
  await o.page.fill("#cp-nom", CLIENT.nom);
  await o.page.fill("#cp-tel", CLIENT.tel);
  await o.page.click("#cp-creer-tel");
  await pause(900);
  await o.page.fill("#cp-code", "123456");
  await pause(400);
  const bouton = await o.page.$("#cp-valider:not([disabled])");
  if (bouton) await bouton.click().catch(() => {});
  await pause(2000);
  const ins = donnees(o.journal, "CompleteRegistration");
  ok(ins.length === 1 && ins[0].content_name === (revendeur ? "revendeur" : "client"),
    quoi + " : une inscription (" + JSON.stringify(ins) + ")");
  ok(traces(o.journal, "Lead").length === (revendeur ? 1 : 0),
    revendeur ? "et sa demande de revendeur, partie une fois le compte ouvert" : "et aucune demande de revendeur");
  tousLesJournaux.push(...o.journal);
  await o.ctx.close();
}
/* PAR L'E-MAIL, quand le SMS est fermé. */
{
  const etat = nouvelEtat();
  etat.smsOuvert = false;
  const o = await ouvrir({ adresse: SITE + "/client/index.html#/inscription", etat });
  await o.page.fill("#cp-nom", CLIENT.nom);
  await o.page.fill("#cp-email", CLIENT.email);
  await o.page.fill("#cp-mdp", "secret-essai");
  await o.page.click("#cp-creer");
  await pause(1500);
  const ins = donnees(o.journal, "CompleteRegistration");
  ok(ins.length === 1 && ins[0].content_name === "client",
    "par l'e-mail (SMS fermé), un compte client : une inscription (" + JSON.stringify(ins) + ")");
  ok(traces(o.journal, "Lead").length === 0, "et aucune demande de revendeur");
  tousLesJournaux.push(...o.journal);
  await o.ctx.close();
}
{
  const etat = nouvelEtat();
  etat.signupConfirmation = true;
  etat.smsOuvert = false;
  const o = await ouvrir({ adresse: SITE + "/client/index.html#/inscription", etat });
  await o.page.click('[data-type="revendeur"]');
  await o.page.fill("#cp-message", CLIENT.commerce);
  await o.page.fill("#cp-nom", CLIENT.nom);
  await o.page.fill("#cp-email", CLIENT.email);
  await o.page.fill("#cp-mdp", "secret-essai");
  await o.page.click("#cp-creer");
  await pause(1500);
  const ins = donnees(o.journal, "CompleteRegistration");
  ok(ins.length === 1 && ins[0].content_name === "revendeur",
    "un revendeur inscrit (confirmation par e-mail en attente) : une inscription (" + JSON.stringify(ins) + ")");
  ok(traces(o.journal, "Lead").length === 1, "et UNE demande de revendeur");
  tousLesJournaux.push(...o.journal);
  await o.ctx.close();
}
{
  const etat = nouvelEtat();
  etat.fiche = { id: "u-client", nom: CLIENT.nom, tel: CLIENT.tel, indicatif: "229", tel_verifie: true,
    type_compte: "client", revendeur_etat: "aucune" };
  const o = await ouvrir({ adresse: SITE + "/client/index.html#/compte", etat,
    avant: { "bizzoo-session": JSON.stringify({ access_token: jeton("u-client"), refresh_token: "r",
      expire_a: Date.now() + 3600000, email: CLIENT.email }) } });
  await pause(800);
  const formulaire = await o.page.$("#cp-rv-demander");
  ok(!!formulaire, "le compte client propose de devenir revendeur");
  if (formulaire) {
    await o.page.fill("#cp-rv-message", CLIENT.commerce);
    await o.page.click("#cp-rv-demander");
    await pause(1500);
  }
  ok(etat.demandes === 1 && traces(o.journal, "Lead").length === 1,
    "la demande envoyée depuis le compte : une demande (" + traces(o.journal, "Lead").length + ")");
  ok(traces(o.journal, "CompleteRegistration").length === 0, "ce n'est pas une inscription");
  tousLesJournaux.push(...o.journal);
  await o.ctx.close();
}

titre("6 bis. Entrer par son numéro : seule la naissance du compte compte");
{
  const maintenant = Date.now();
  const essais = [
    ["un numéro inconnu crée le compte", { id: "u-neuf", phone: "2290196000001",
      created_at: new Date(maintenant - 20000).toISOString(), last_sign_in_at: new Date(maintenant).toISOString() }, 1],
    ["un client qui revient n'est pas un inscrit", { id: "u-ancien", phone: "2290196000001",
      created_at: "2026-08-01T10:00:00Z", last_sign_in_at: new Date(maintenant).toISOString() }, 0],
  ];
  for (const [quoi, user, attendu] of essais) {
    const etat = nouvelEtat();
    etat.verifyUser = user;
    const o = await ouvrir({ adresse: SITE + "/client/index.html#/connexion-tel", etat });
    for (let tour = 0; tour < 2; tour++) {
      if (tour === 1) {
        await o.page.evaluate(() => localStorage.removeItem("bizzoo-session"));
        await aller(o.page, "#/");
        await aller(o.page, "#/connexion-tel");
      }
      await o.page.fill("#cp-tel", CLIENT.tel);
      await o.page.click("#cp-envoyer");
      await pause(900);
      /* Le sixième chiffre valide tout seul ; « Valider » ne sert qu'à
         qui l'aurait raté. */
      await o.page.fill("#cp-code", "123456");
      await pause(400);
      const bouton = await o.page.$("#cp-valider:not([disabled])");
      if (bouton) await bouton.click().catch(() => {});
      await pause(1500);
    }
    const n = traces(o.journal, "CompleteRegistration").length;
    ok(n === attendu, quoi + ", même entré deux fois (" + n + " inscription)");
    tousLesJournaux.push(...o.journal);
    await o.ctx.close();
  }
}

/* =====================================================
   7. La recherche
   ===================================================== */

titre("7. La recherche : ce qu'on a fini de taper, une fois");
{
  const o = await ouvrir({ adresse: SITE + "/client/index.html#/recherche" });
  const recherches = () => donnees(o.journal, "Search").map((x) => x.search_string);
  await o.page.type("#recherche-champ", "or", { delay: 60 });
  await pause(500);
  ok(recherches().length === 0, "pendant qu'on tape, rien ne part");
  await o.page.type("#recherche-champ", "di", { delay: 60 });
  await pause(1900);
  ok(JSON.stringify(recherches()) === '["ordi"]', "une pause : « ordi » part (" + JSON.stringify(recherches()) + ")");
  await o.page.type("#recherche-champ", "nateur", { delay: 40 });
  await o.page.press("#recherche-champ", "Enter");
  await pause(300);
  ok(JSON.stringify(recherches()) === '["ordi","ordinateur"]', "Entrée : « ordinateur » part aussitôt");
  await pause(1900);
  ok(recherches().length === 2, "et la pause qui suit ne le redit pas (" + recherches().length + ")");
  for (const [mot, quoi] of [[CLIENT.tel, "un numéro de téléphone"], [CLIENT.email, "une adresse e-mail"], ["o", "une seule lettre"]]) {
    await o.page.fill("#recherche-champ", "");
    await o.page.type("#recherche-champ", mot, { delay: 15 });
    await o.page.press("#recherche-champ", "Enter");
    await pause(1900);
    ok(recherches().length === 2, quoi + " tapé dans la recherche ne part pas (" + recherches().length + ")");
  }
  tousLesJournaux.push(...o.journal);
  await o.ctx.close();
}

/* =====================================================
   8. Le contact
   ===================================================== */

titre("8. Le contact : WhatsApp, téléphone, e-mail — pas le partage");
{
  const o = await ouvrir({ adresse: SITE + "/client/index.html#/produit/prod_a" });
  const contacts = () => donnees(o.journal, "Contact").map((x) => x.content_name);
  const lien = await o.page.$('a[href^="https://wa.me/229"]');
  ok(!!lien, "la fiche produit porte un lien WhatsApp vers la boutique");
  if (lien) await lien.click();
  await pause(300);
  ok(JSON.stringify(contacts()) === '["whatsapp"]', "un clic WhatsApp : un contact (" + JSON.stringify(contacts()) + ")");
  await o.page.evaluate(() => {
    const zone = document.createElement("div");
    zone.style.cssText = "position:fixed;top:80px;left:10px;z-index:99999;display:flex;gap:16px;background:#fff";
    zone.innerHTML = '<a id="t-tel" href="tel:+2290197000000">Appeler</a>' +
      '<a id="t-mail" href="mailto:contact@bizzoomarket.com">Écrire</a>' +
      '<a id="t-partage" href="https://wa.me/?text=Regarde%20ce%20produit">Partager</a>';
    document.body.appendChild(zone);
  });
  await o.page.click("#t-tel");
  await o.page.click("#t-mail");
  await o.page.click("#t-partage");
  await pause(300);
  ok(JSON.stringify(contacts()) === '["whatsapp","telephone","email"]',
    "le téléphone et l'e-mail aussi ; le partage, non (" + JSON.stringify(contacts()) + ")");
  tousLesJournaux.push(...o.journal);
  await o.ctx.close();
}

/* =====================================================
   9. Rien de personnel, jamais de jeton
   ===================================================== */

titre("9. Le lien « mot de passe oublié » : aucun jeton ne part");
{
  const o = await ouvrir({ adresse: SITE + "/#access_token=JETON-SECRET&refresh_token=AUSSI-SECRET" +
    "&expires_in=3600&type=recovery" });
  await pause(1500);
  const vues = traces(o.journal, "PageView");
  ok(vues.length >= 1 && /#\/nouveau-mot-de-passe$/.test(vues[vues.length - 1].url),
    "la boutique s'ouvre sur « nouveau mot de passe », et la page vue le dit (" +
    vues.map((v) => v.url.replace(SITE, "")).join(", ") + ")");
  const onglet = await o.page.evaluate(() => JSON.parse(sessionStorage.getItem("banc-pixel") || "[]"));
  ok(o.journal.concat(onglet).every((e) => !/SECRET|access_token|refresh_token/.test(e.url + JSON.stringify(e.args))),
    "aucun appel au pixel ne porte le jeton, ni dans l'adresse, ni dans les données — vitrine comprise (" +
    onglet.length + " appels relus)");
  tousLesJournaux.push(...o.journal);
  await o.ctx.close();
}

titre("9 bis. Ce qui part, sur tout le banc");
{
  const tout = JSON.stringify(tousLesJournaux);
  const fuites = PERSONNEL.filter((x) => tout.includes(x));
  ok(!fuites.length, "aucun nom, numéro, adresse ou e-mail dans " + tousLesJournaux.length +
    " appels au pixel" + (fuites.length ? " — trouvé : " + fuites.join(", ") : ""));
  const valeurs = tousLesJournaux.filter((e) => e.args[0] === "track" && e.args[2] && "value" in e.args[2]);
  ok(valeurs.length > 0 && valeurs.every((e) => Number.isInteger(e.args[2].value) && e.args[2].currency === "XOF"),
    valeurs.length + " montants, tous en nombre entier et en XOF");
  const noms = [...new Set(tousLesJournaux.filter((e) => e.args[0] === "track").map((e) => e.args[1]))].sort();
  const attendus = ["AddPaymentInfo", "AddToCart", "CompleteRegistration", "Contact", "InitiateCheckout",
    "Lead", "PageView", "Purchase", "Search", "ViewContent"];
  ok(JSON.stringify(noms) === JSON.stringify(attendus),
    "les dix événements, et pas un autre (" + noms.join(", ") + ")");
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mLe pixel dit ce qui se passe, au bon moment, une seule fois, et rien de personnel ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
