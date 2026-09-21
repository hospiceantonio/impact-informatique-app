/* =========================================================
   La pastille, le panneau et la commande visée — boutique
   =========================================================
   QUATRE RÈGLES Y SONT ÉPROUVÉES, et chacune a déjà coûté
   quelque chose dans ce projet :

   1. LE DOIGT MÈNE À LA BONNE COMMANDE. « BZ-000123 est payée »
      doit poser le doigt SUR BZ-000123, pas sur une liste de
      quarante. Le constat regarde donc quelle carte porte la
      marque, pas seulement l'adresse de la page.

   2. UNE COMMANDE INTROUVABLE NE CASSE RIEN. Archivée, ou d'une
      boutique qui n'est pas la sienne : on montre la liste
      entière plutôt qu'un écran vide.

   3. MARQUER LU N'ÉCRIT QUE « lue_le », ET SANS RÉCLAMER LA
      LIGNE. C'est la leçon de « Marquer vue » : sans
      « return=minimal », PostgREST ajoute « returning * », et la
      base refuse l'écriture entière. Le constat porte donc sur
      l'EN-TÊTE, que l'écran ne montre pas.

   4. LE LIVREUR SE CHOISIT PAR SON NOM. « porteur@impact.bj »
      ne dit pas qui c'est ; « Rohim » si. Et celui qui n'a pas
      encore de nom garde son adresse, plutôt qu'un bouton vide.

   ET LA DOUBLURE GARDE CE QU'ON LUI ÉCRIT : une doublure qui
   oublie les écritures ne représente pas une base, elle
   représente une base en panne.
   ========================================================= */
/* Playwright n'est pas une dépendance du projet : le chemin se donne
   par PLAYWRIGHT, le navigateur par CHROMIUM, l'adresse par BANC_URL. */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-notifications-admin.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const MOI = "22222222-2222-2222-2222-222222222222";
const PORTEUR = "cccccccc-1111-1111-1111-111111111111";
const BOU = [{ id: "bou_tech", nom: "IMPACT", secteur: "Informatique",
  categorie_id: "cat_h", icone: "portable", couleur: "#0B5CF5", devise: "FCFA",
  indicatif: "229", actif: true, ordre: 1 }];

const LIGNE = (id, cmd, etat) => ({ id, commande_id: cmd, boutique_id: "bou_tech",
  produit_id: "p1", nom: "Chargeur", code: "0001", reference: "", prix: 6000,
  quantite: 1, etat, cree_le: "2026-09-12T09:00:00Z", confirme_le: null,
  livreur_id: null });
const CMD = [
  { id: "cmd_a", numero: "BZ-000001", client_nom: "Kofi", client_tel: "97222222",
    client_indicatif: "229", client_adresse: "Godomey", note: "", total: 6000,
    devise: "FCFA", etat: "payee", transaction_id: "t1", confirme_par: "",
    remarque: "", paye_le: "2026-09-12T09:02:00Z", cree_le: "2026-09-12T09:00:00Z",
    commande_lignes: [LIGNE("lig_a", "cmd_a", "preparee")] },
  { id: "cmd_b", numero: "BZ-000002", client_nom: "Ama", client_tel: "97333333",
    client_indicatif: "229", client_adresse: "Cotonou", note: "", total: 9000,
    devise: "FCFA", etat: "payee", transaction_id: "t2", confirme_par: "",
    remarque: "", paye_le: "2026-09-12T09:03:00Z", cree_le: "2026-09-12T09:01:00Z",
    commande_lignes: [LIGNE("lig_b", "cmd_b", "nouvelle")] },
];

const maintenant = Date.now();
const N = (id, type, t, corps, lien, lue, ilya) => ({
  id, type, titre: t, corps, lien, commande_id: "cmd_a", boutique_id: "bou_tech",
  sonne: true, lue_le: lue ? "2026-09-20T10:00:00Z" : null,
  cree_le: new Date(maintenant - ilya).toISOString(),
});

let NOTIFS = [];
let LIVREURS = [];
let ecritures = [];

async function ouvrir({ connecte = true } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1900 } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({
      url: "https://base-absente.invalid", cle: "cle-de-banc" }));
    if (!a.connecte) { localStorage.removeItem("impact-session"); return; }
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: a.moi }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: "chef@impact.bj" }));
  }, { connecte, moi: MOI });

  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    if (req.method() !== "GET") {
      ecritures.push({ methode: req.method(), chemin: c + u.search,
        prefer: req.headers()["prefer"] || "",
        corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })() });
    }
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json",
      body: JSON.stringify(x) });
    /* LA DOUBLURE GARDE CE QU'ON LUI ÉCRIT. Sans cela, « tout marquer
       lu » serait défait par la relecture qui suit, et le banc verrait
       un défaut qui n'existe que dans le banc. */
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
    if (c === "rpc/livreurs_boutique") return d(LIVREURS);
    if (c === "rpc/assigner_livreur") return d(1);
    if (req.method() === "PATCH") return route.fulfill({ status: 204, body: "" });
    if (c.startsWith("profils")) return d([{ id: MOI, email: "chef@impact.bj",
      nom: "", tel: "", role: "administrateur", actif: true,
      peut_modifier_produits: true, boutique_id: "bou_tech" }]);
    if (c.startsWith("commandes")) return d(CMD);
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

/* ------------------------------------------------------------------ */
NOTIFS = [
  N(1, "commande_payee", "Nouvelle commande payée", "La commande BZ-000001 est payée.",
    "#/commandes/cmd_a", false, 30000),
  N(2, "reception_confirmee", "Le client a confirmé la réception",
    "Commande BZ-000001 — le client déclare avoir tout reçu.",
    "#/commandes/cmd_a", false, 600000),
  N(3, "course_confiee", "Course confiée à un livreur", "Commande BZ-000001.",
    "#/commandes/cmd_a", true, 7200000),
];
LIVREURS = [
  { id: PORTEUR, email: "porteur@impact.bj", nom: "Rohim", tel: "0197000011", actif: true },
  { id: "cccccccc-2222-2222-2222-222222222222", email: "sans-nom@impact.bj",
    nom: "", tel: "", actif: true },
];

titre("La cloche est dans la barre, avec son compte");
{
  const { page, ctx } = await ouvrir();
  const m = await page.evaluate(() => {
    const c = document.querySelector(".btn-cloche");
    return { existe: !!c,
      pastille: c ? (c.querySelector(".cloche-pastille") || {}).textContent || "" : "",
      etiquette: c ? c.getAttribute("aria-label") : "" };
  });
  ok(m.existe, "la cloche est là");
  ok(m.pastille === "2", "et porte le nombre de non lues (" + m.pastille + ")");
  ok(/2 non lues/.test(m.etiquette), "le nombre est aussi dans l'étiquette");
  await ctx.close();
}

titre("Déconnecté, aucune cloche : il n'y a personne à prévenir");
{
  const { page, ctx } = await ouvrir({ connecte: false });
  const m = await page.evaluate(() => ({
    cloche: !!document.querySelector(".btn-cloche"),
    ecran: document.body.innerText.slice(0, 80),
  }));
  ok(!m.cloche, "aucune cloche sur l'écran de connexion");
  await ctx.close();
}

titre("Le panneau groupe, et le doigt mène à la commande");
{
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/notifications"; });
  await page.waitForTimeout(1600);
  const m = await page.evaluate(() => {
    const lignes = [...document.querySelectorAll("#vue .notif")];
    return { combien: lignes.length,
      points: lignes.filter((l) => l.querySelector(".notif-point")).length,
      premier: lignes.length ? lignes[0].getAttribute("href") : "",
      texte: document.body.innerText };
  });
  ok(m.combien === 3, "les trois notifications sont là (" + m.combien + ")");
  ok(m.points === 2, "deux points bleus (" + m.points + ")");
  ok(m.premier === "#/commandes/cmd_a",
    "le doigt mène à la commande (" + m.premier + ")");
  ok(/Commandes payées/.test(m.texte), "une section « Commandes payées »");
  ok(/Réceptions confirmées/.test(m.texte), "une section « Réceptions confirmées »");
  await ctx.close();
}

titre("Le lien ouvre l'écran des commandes SUR la bonne commande");
{
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/commandes/cmd_a"; });
  await page.waitForTimeout(2200);
  const m = await page.evaluate(() => {
    const visee = document.querySelector(".cmd-visee");
    return { ou: location.hash,
      visee: visee ? visee.getAttribute("data-commande") : "",
      combien: document.querySelectorAll("[data-commande]").length };
  });
  ok(m.ou === "#/commandes/cmd_a", "on est bien sur l'écran des commandes");
  ok(m.combien >= 2, "la liste entière est là (" + m.combien + " commandes)");
  ok(m.visee === "cmd_a", "et c'est cmd_a qui est visée (" + m.visee + ")");
  await ctx.close();
}

titre("Une commande introuvable ne casse rien");
{
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/commandes/cmd_disparue"; });
  await page.waitForTimeout(2200);
  const m = await page.evaluate(() => ({
    combien: document.querySelectorAll("[data-commande]").length,
    visee: document.querySelectorAll(".cmd-visee").length,
  }));
  ok(m.combien >= 2, "la liste s'affiche quand même (" + m.combien + ")");
  ok(m.visee === 0, "rien n'est visé, et c'est tout");
  await ctx.close();
}

titre("Marquer lu n'écrit que « lue_le », et sans réclamer la ligne");
{
  ecritures = [];
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/notifications"; });
  await page.waitForTimeout(1600);
  await page.evaluate(() => document.querySelector("#vue .notif").click());
  await page.waitForTimeout(900);
  const e = ecritures.find((x) => /^notifications\?/.test(x.chemin));
  ok(!!e, "une modification part vers la base");
  ok(e && e.corps && e.corps.lue_le && Object.keys(e.corps).length === 1,
    "et n'écrit QUE « lue_le »");
  /* LA LEÇON DE « MARQUER VUE » : sans « return=minimal », PostgREST
     ajoute « returning * » et réclame toute la ligne — la base refuse
     alors l'écriture entière. */
  ok(e && /minimal/.test(e.prefer),
    "elle ne réclame pas la ligne en retour (Prefer: " + (e ? e.prefer : "") + ")");
  await ctx.close();
}

titre("Confier une course : le livreur se choisit par son NOM");
{
  ecritures = [];
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/commandes"; });
  await page.waitForTimeout(1900);
  await page.evaluate(() => {
    const b = [...document.querySelectorAll("button")]
      .find((x) => /confier/i.test(x.textContent));
    if (b) b.click();
  });
  await page.waitForTimeout(1500);
  const m = await page.evaluate(() => {
    const boutons = [...document.querySelectorAll("[data-livreur]")];
    return { textes: boutons.map((b) => b.textContent.trim()),
      combien: boutons.length };
  });
  ok(m.combien >= 2, "la feuille liste les livreurs (" + m.combien + ")");
  ok(m.textes.some((t) => /Rohim/.test(t)),
    "le livreur paraît sous son NOM (" + (m.textes[0] || "") + ")");
  ok(m.textes.some((t) => /0197000011/.test(t)), "avec son numéro dessous");
  /* UN LIVREUR SANS NOM RESTE CHOISISSABLE : son adresse prend la
     place, plutôt qu'un bouton vide. */
  ok(m.textes.some((t) => /sans-nom@impact\.bj/.test(t)),
    "et celui qui n'a pas de nom garde son adresse");
  await ctx.close();
}

await nav.close();
console.log("\n" + (echecs ? "  " + echecs + " ÉCHEC(S)" : "  Tout passe."));
process.exit(echecs ? 1 : 0);
