/* =========================================================
   Créer un livreur : son nom, son numéro, et pour qui il porte
   =========================================================
   CE QUE CE BANC ÉPROUVE, ET POURQUOI IL EXISTE. Un livreur
   avait bien un nom et un numéro EN BASE, et la fiche d'un
   compte savait les écrire. Mais l'ÉCRAN DE CRÉATION, lui, ne
   les demandait pas — et n'offrait même pas le rang « Livreur ».
   Résultat, sur la vraie base du gérant : un livreur créé sans
   nom et sans numéro, que « Confier à un livreur » affichait
   par son adresse e-mail. Rien n'était rouge nulle part.

   Les constats portent donc sur CE QUI PART VERS LA BASE, pas
   sur ce que l'écran montre. Un champ peut être à l'écran et
   n'être envoyé nulle part : c'est exactement la panne qu'on
   vient de réparer, et un banc qui regarde l'écran ne la voit
   pas.

   Quatre choses à prouver :

     1. LE RANG « LIVREUR » EST DANS LE MENU DE CRÉATION ;
     2. LE NOM ET LE NUMÉRO SONT DEMANDÉS, ET ENVOYÉS ;
     3. « BIZZOO » EST OFFERT POUR UN LIVREUR, et part bien en
        « aucune boutique » — plus de refus ;
     4. LA FEUILLE « CONFIER » DIT QUI N'EST PAS DE LA MAISON.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-livreur-bizzoo.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const MOI = "11111111-1111-1111-1111-111111111111";
const PORTEUR = "cccccccc-1111-1111-1111-111111111111";
const TOURNEE = "cccccccc-9999-9999-9999-999999999999";
const NEUF = "dddddddd-0000-0000-0000-000000000001";

const BOU = [
  { id: "bou_tech", nom: "IMPACT", secteur: "Informatique", categorie_id: "cat_h",
    icone: "portable", couleur: "#0B5CF5", devise: "FCFA", indicatif: "229",
    actif: true, ordre: 1 },
  { id: "bou_mode", nom: "CREATIS", secteur: "Mode", categorie_id: "cat_m",
    icone: "sac", couleur: "#E11", devise: "FCFA", indicatif: "229",
    actif: true, ordre: 2 },
];

const LIGNE = { id: "lig_a", commande_id: "cmd_a", boutique_id: "bou_tech",
  produit_id: "p1", nom: "Chargeur", code: "0001", reference: "", prix: 6000,
  quantite: 1, etat: "preparee", cree_le: "2026-09-12T09:00:00Z",
  confirme_le: null, livreur_id: null };
const CMD = [{ id: "cmd_a", numero: "BZ-000001", client_nom: "Kofi",
  client_tel: "97222222", client_indicatif: "229", client_adresse: "Godomey",
  note: "", total: 6000, devise: "FCFA", etat: "payee", transaction_id: "t1",
  confirme_par: "", remarque: "", paye_le: "2026-09-12T09:02:00Z",
  cree_le: "2026-09-12T09:00:00Z", commande_lignes: [LIGNE] }];

/* Deux porteurs : celui de la boutique, et celui de l'enseigne.
   C'est la colonne « bizzoo » qui les distingue, comme en base. */
const LIVREURS = [
  { id: PORTEUR, email: "porteur@impact.bj", nom: "Rohim", tel: "0197000011",
    actif: true, bizzoo: false },
  { id: TOURNEE, email: "tournee@bizzoo.bj", nom: "Ablo", tel: "0197000099",
    actif: true, bizzoo: true },
];

/* Les comptes de la liste. Le dernier est un livreur de BIZZOO : sa
   boutique est vide, et ce vide est un CHOIX, pas un oubli. */
let COMPTES = [
  { id: MOI, email: "chef@bizzoo.bj", nom: "", tel: "", role: "superadministrateur",
    actif: true, peut_modifier_produits: true, boutique_id: null },
  { id: PORTEUR, email: "porteur@impact.bj", nom: "Rohim", tel: "0197000011",
    role: "livreur", actif: true, peut_modifier_produits: true, boutique_id: "bou_tech" },
  { id: TOURNEE, email: "tournee@bizzoo.bj", nom: "Ablo", tel: "0197000099",
    role: "livreur", actif: true, peut_modifier_produits: true, boutique_id: null },
];

let ecritures = [];

async function ouvrir() {
  ecritures = [];
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1900 } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({
      url: "https://base-absente.invalid", cle: "cle-de-banc" }));
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: a.moi }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: "chef@bizzoo.bj" }));
  }, { moi: MOI });

  /* LA CRÉATION D'UN COMPTE PASSE PAR AUTH, pas par la table : sans
     cette doublure-là, le bouton « Créer » s'arrêterait avant d'avoir
     rien envoyé à « profils », et les constats qui suivent ne
     verraient rien — verts pour la mauvaise raison. */
  await page.route("**/auth/v1/**", (route) => {
    const u = new URL(route.request().url());
    if (u.pathname.endsWith("/signup")) {
      return route.fulfill({ status: 200, contentType: "application/json",
        body: JSON.stringify({ user: { id: NEUF, email: "neuf@impact.bj",
          email_confirmed_at: "2026-09-22T10:00:00Z",
          identities: [{ provider: "email" }] }, access_token: "a" }) });
    }
    return route.fulfill({ status: 200, contentType: "application/json", body: "{}" });
  });

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
    if (c === "rpc/livreurs_boutique") return d(LIVREURS);
    if (c === "rpc/assigner_livreur") return d(1);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("profils")) {
      if (req.method() !== "GET") return route.fulfill({ status: 204, body: "" });
      return d(COMPTES);
    }
    if (req.method() !== "GET") return route.fulfill({ status: 204, body: "" });
    if (c.startsWith("notifications")) return d([]);
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
titre("1. Le rang « Livreur » est dans le menu de création");
{
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/comptes"; });
  await page.waitForTimeout(1500);
  await page.click("#cp-nouveau");
  await page.waitForTimeout(700);
  const m = await page.evaluate(() => {
    const menu = document.querySelector("#nc-role");
    return {
      rangs: menu ? [...menu.options].map((o) => o.value) : [],
      nom: !!document.querySelector("#nc-nom"),
      tel: !!document.querySelector("#nc-tel"),
    };
  });
  ok(m.rangs.includes("livreur"),
    "« Livreur » se choisit à la création (" + m.rangs.join(", ") + ")");
  /* LE CHAMP DOIT ÊTRE LÀ AVANT D'ÊTRE ENVOYÉ : sans lui, il n'y a
     rien à remplir, et le compte part avec son adresse pour seul nom. */
  ok(m.nom, "le champ « Nom » est demandé");
  ok(m.tel, "le champ « Téléphone » aussi");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("2. Le nom et le numéro PARTENT vers la base");
{
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/comptes"; });
  await page.waitForTimeout(1500);
  await page.click("#cp-nouveau");
  await page.waitForTimeout(700);
  await page.fill("#nc-email", "neuf@impact.bj");
  await page.fill("#nc-mdp", "motdepasse");
  await page.fill("#nc-nom", "Ablo");
  await page.fill("#nc-tel", "0197000099");
  await page.selectOption("#nc-role", "livreur");
  await page.selectOption("#nc-boutique", "bou_tech");
  await page.click("#nc-creer");
  await page.waitForTimeout(1400);

  const pose = ecritures.find((e) => e.methode === "POST" && /^profils/.test(e.chemin));
  ok(!!pose, "la fiche du compte part bien vers « profils »");
  /* LE CONSTAT QUI COMPTE. Le champ peut être à l'écran et n'aller
     nulle part — c'est la panne qu'on répare ici. On regarde donc
     l'envoi, pas le formulaire. */
  ok(!!pose && pose.corps && pose.corps.nom === "Ablo",
    "avec son NOM (" + JSON.stringify(pose && pose.corps && pose.corps.nom) + ")");
  ok(!!pose && pose.corps && pose.corps.tel === "0197000099",
    "et son NUMÉRO (" + JSON.stringify(pose && pose.corps && pose.corps.tel) + ")");
  ok(!!pose && pose.corps && pose.corps.role === "livreur",
    "et le rang « livreur »");
  ok(!!pose && pose.corps && pose.corps.boutique_id === "bou_tech",
    "et sa boutique");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("3. « BIZZOO » est offert pour un livreur, et part en « aucune boutique »");
{
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/comptes"; });
  await page.waitForTimeout(1500);
  await page.click("#cp-nouveau");
  await page.waitForTimeout(700);
  await page.selectOption("#nc-role", "livreur");
  await page.waitForTimeout(250);

  const menu = await page.evaluate(() => {
    const m = document.querySelector("#nc-boutique");
    return { choix: m ? [...m.options].map((o) => o.value) : [],
      aide: (document.querySelector("#nc-boutique-aide") || {}).textContent || "" };
  });
  ok(menu.choix.includes("__enseigne"),
    "le menu propose BIZZOO à un livreur (" + menu.choix.join(", ") + ")");
  /* L'AIDE DIT CE QUE « BIZZOO » VEUT DIRE ICI. Le même mot désigne un
     compte qui gouverne toutes les boutiques et un porteur qui les
     sert toutes : une phrase figée en décrirait un et tromperait sur
     l'autre. */
  ok(/porte|livreur de l'enseigne|confier une course/i.test(menu.aide),
    "et l'aide parle bien d'un PORTEUR, pas d'un compte de l'enseigne");
  ok(/aucun autre droit/i.test(menu.aide),
    "en disant qu'il ne gagne aucun droit pour autant");

  await page.fill("#nc-email", "tournee@bizzoo.bj");
  await page.fill("#nc-mdp", "motdepasse");
  await page.fill("#nc-nom", "Ablo");
  await page.fill("#nc-tel", "0197000099");
  await page.selectOption("#nc-boutique", "__enseigne");
  await page.click("#nc-creer");
  await page.waitForTimeout(1400);

  const pose = ecritures.find((e) => e.methode === "POST" && /^profils/.test(e.chemin));
  ok(!!pose, "la création n'est plus refusée");
  ok(!!pose && pose.corps && pose.corps.boutique_id === null,
    "et le livreur part sans boutique — donc pour toutes");
  const erreur = await page.evaluate(() =>
    (document.querySelector("#nc-resultat") || {}).textContent || "");
  ok(!/porte pour une boutique/i.test(erreur),
    "et l'ancien refus a disparu de l'écran");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("4. La liste des comptes ne prend plus ce choix pour un oubli");
{
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/comptes"; });
  await page.waitForTimeout(1600);
  const texte = await page.evaluate(() => document.body.innerText);
  ok(/BIZZOO — porte pour toutes les boutiques/.test(texte),
    "le livreur de BIZZOO est nommé comme tel");
  /* « boutique à choisir » est ce que la liste écrivait pour une
     boutique vide. Sur un livreur de BIZZOO, c'était traiter une
     décision comme une fiche mal remplie. */
  ok(!/Livreur · boutique à choisir/.test(texte),
    "et non « boutique à choisir », qui en ferait une erreur");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("5. « Confier » dit qui n'est pas de la maison");
{
  const { page, ctx } = await ouvrir();
  await page.evaluate(() => { location.hash = "#/commandes"; });
  await page.waitForTimeout(1600);
  const ouvert = await page.evaluate(() => {
    const b = [...document.querySelectorAll("button")]
      .find((x) => /Confier à un livreur/.test(x.textContent));
    if (b) b.click();
    return !!b;
  });
  ok(ouvert, "le bouton « Confier à un livreur » est là");
  await page.waitForTimeout(900);
  const m = await page.evaluate(() => {
    const lignes = [...document.querySelectorAll(".cmd-livreur")];
    return lignes.map((l) => ({
      nom: (l.querySelector(".cmd-livreur-nom") || {}).textContent || "",
      marque: !!l.querySelector(".cmd-livreur-bizzoo"),
      tel: (l.querySelector(".cmd-livreur-tel") || {}).textContent || "",
    }));
  });
  ok(m.length === 2, "les deux porteurs sont proposés (" + m.length + ")");
  const sien = m.find((x) => /Rohim/.test(x.nom));
  const enseigne = m.find((x) => /Ablo/.test(x.nom));
  ok(!!sien && !sien.marque, "son porteur à elle ne porte aucune marque");
  ok(!!enseigne && enseigne.marque, "celui de BIZZOO est marqué « BIZZOO »");
  ok(!!enseigne && enseigne.tel === "0197000099",
    "et son numéro part avec (" + (enseigne || {}).tel + ")");
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec.\n"
  : "\nCréer un livreur : le rang, le nom, le numéro et BIZZOO tiennent ✔\n");
process.exit(echecs ? 1 : 0);
