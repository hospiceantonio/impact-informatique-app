/* =========================================================
   Le parcours de livraison, à l'écran (3.59.0)
   =========================================================
   La base fait la fiche, l'alerte et la notification « Votre livreur »
   (supabase/tests/99zzzzzzzzz-parcours-livraison.sql). Ce banc regarde
   ce que les ÉCRANS en font :

     1. l'application admin du livreur : la fiche complète (récupérer,
        livrer à, destinataire, frais, déjà payé, à récupérer), et
        « Reçu » qui appelle « accepter_course » ;
     2. une course acceptée : plus de « Reçu », « Je l'ai prise » ;
     3. une base d'avant (sans fiche) : l'écran d'avant, sans « Reçu » ;
     4. (3.66.0) « Mes courses » de l'application client renvoie vers
        BIZZOO Admin, sans rien lister ;
     5. les notifications s'affichent sur plusieurs lignes (admin et
        client), et « Votre livreur » a sa famille ;
     6. LES DEMANDES envoyées à tous dès le paiement (dans l'admin) : en
        tête de « Mes courses », groupée avec un lieu par boutique ;
        « Commande reçue » appelle prendre_course ; « trop tard » se dit.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-parcours-livraison.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const F = (n) => n.toLocaleString("fr-FR").replace(/ | /g, " ") + " FCFA";
const plat = (s) => s.replace(/[  ]/g, " ").replace(/\s+/g, " ");

const FICHE = {
  numero: "BZ-000077",
  retrait: { boutique: "Alpha", adresse: "Ganhi, rue du marché", tel: "0197111222", indicatif: "229",
    latitude: null, longitude: null },
  livraison: { nom: "Afi", adresse: "Fidjrossè, près de l'église", note: "Sonner deux fois",
    tel: "97666005", indicatif: "229" },
  devise: "FCFA", frais: 1000, deja_paye: 3000, a_encaisser: 7000,
};
const course = (o) => ({ commande_id: "cmd_p", numero: "BZ-000077", boutique_id: "bou_a",
  nom_boutique: "Alpha", client_nom: "Afi", client_tel: "97666005", client_indicatif: "229",
  client_adresse: "Fidjrossè, près de l'église", note: "Sonner deux fois", etat: "preparee",
  articles: [{ nom: "Imprimante", code: "0009", quantite: 1 }], paye_le: "2026-10-19T08:00:00Z",
  a_encaisser: 7000, fiche: FICHE, recu_le: null, ...o });

const DEMANDE = { commande_id: "cmd_g", numero: "BZ-000088", paye_le: "2026-10-19T08:00:00Z",
  fiche: { numero: "BZ-000088", groupee: true, lieu_retrait: "Bêta : marché Dantokpa, porte 3\nAppeler Rémi",
    retraits: [
      { boutique_id: "bou_a", boutique: "Alpha", adresse: "Ganhi", tel: "0197111222", indicatif: "229", a_encaisser: 3000 },
      { boutique_id: "bou_b", boutique: "Bêta", adresse: "Dantokpa", tel: "0197333444", indicatif: "229", a_encaisser: 2000 }],
    livraison: { nom: "Koffi", adresse: "Akpakpa", note: "", tel: "97000009", indicatif: "229" },
    devise: "FCFA", frais: 2000, deja_paye: 5000, a_encaisser: 5000 } };

const NOTIF = { id: "n1", destinataire: "x", type: "course_acceptee", commande_id: "cmd_p",
  titre: "Votre livreur : Rachidi", corps: "Commande BZ-000077 — Alpha\nSon numéro : +229 0196777888 — appelez-le si besoin.",
  lue: false, cree_le: new Date().toISOString() };

/* ================================================================
   L'application admin
   ================================================================ */
const PORTEUR = "cccccccc-1111-1111-1111-111111111111";
const PROFIL = { id: PORTEUR, email: "porteur@alpha.bj", nom: "Rachidi", role: "livreur", actif: true,
  peut_modifier_produits: true, boutique_id: "bou_a" };

async function ouvrirAdmin({ courses, hash, demandes = [], tropTard = false }) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2000 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: a.moi }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
  }, { moi: PORTEUR, email: PROFIL.email });
  const serveur = { appels: [] };
  let liste = courses;
  let proposees = demandes;
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) {
      serveur.appels.push({ fn: c.slice(4), corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })() });
    }
    if (c.startsWith("profils")) return d([PROFIL]);
    /* Le livreur a validé sa position (3.58.0). */
    if (c.startsWith("positions_livreurs")) return d([{ profil_id: PORTEUR, latitude: 6.37,
      longitude: 2.42, adresse: "Cadjèhoun" }]);
    if (c === "rpc/mes_livraisons") return d(liste);
    if (c === "rpc/accepter_course") {
      liste = liste.map((l) => ({ ...l, recu_le: "2026-10-19T09:00:00Z" }));
      return d(1);
    }
    if (c === "rpc/courses_proposees") return d(proposees);
    if (c === "rpc/prendre_course") {
      proposees = [];
      if (tropTard) {
        return route.fulfill({ status: 400, contentType: "application/json",
          body: JSON.stringify({ code: "P0001", message: "Trop tard : un autre livreur a déjà pris cette course." }) });
      }
      liste = [course({ commande_id: "cmd_g", numero: "BZ-000088", etat: "nouvelle", recu_le: "2026-10-19T09:00:00Z" })];
      return d(2);
    }
    if (c.startsWith("notifications")) return d([NOTIF]);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  if (hash) {
    await page.evaluate((h) => { location.hash = h; }, hash);
    await page.waitForTimeout(1500);
  }
  return { page, ctx, erreurs, serveur };
}

titre("1. Le livreur (admin) : la fiche complète, et « Commande reçue »");
{
  const { page, ctx, erreurs, serveur } = await ouvrirAdmin({ courses: [course()] });
  await page.waitForSelector(".lv-course", { timeout: 6000 }).catch(() => {});
  const t = plat(await page.evaluate(() => (document.querySelector(".lv-course") || {}).innerText || ""));
  ok(/Récupérer le colis/i.test(t) && /Alpha/.test(t) && /Ganhi, rue du marché/.test(t),
    "où récupérer : la boutique et son adresse");
  ok(/Livrer à/i.test(t) && /Afi/.test(t) && /Fidjrossè, près de l'église/.test(t), "où livrer : le nom et l'adresse");
  ok(await page.evaluate(() => !!document.querySelector('.lv-course a[href="tel:+22997666005"]')),
    "le numéro du destinataire, appelable");
  ok(t.includes("Frais de livraison : " + F(1000)), "les frais de livraison");
  ok(t.includes("Déjà payé par le client : " + F(3000)), "ce que le client a déjà payé");
  ok(t.includes("À payer par MoMoPay : " + F(7000)), "ce qu'il reste à récupérer");
  ok(!t.includes(F(9000)), "pas le prix des articles");
  ok(/Sonner deux fois/.test(t), "la note du client");
  ok(await page.evaluate(() => !document.querySelector(".lv-lieu-saisi")),
    "une commande de l'application : pas de « Où récupérer (précisé par BIZZOO) »");
  ok(await page.evaluate(() => !!document.querySelector(".lv-recu") && !document.querySelector(".lv-avancer")),
    "« Reçu » d'abord, pas encore « Je l'ai prise »");

  await page.click(".lv-recu");
  await page.waitForTimeout(1500);
  const appel = serveur.appels.find((a) => a.fn === "accepter_course");
  ok(appel && appel.corps && appel.corps.commande === "cmd_p" && appel.corps.boutique === "bou_a",
    "« Reçu » appelle accepter_course(cmd_p, bou_a)");

  titre("2. Acceptée : « Je l'ai prise »");
  ok(await page.evaluate(() => !document.querySelector(".lv-recu") &&
    (document.querySelector(".lv-avancer") || {}).dataset.vers === "en_livraison"),
    "plus de « Reçu » ; « Je l'ai prise » apparaît");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx } = await ouvrirAdmin({ courses: [course({ etat: "en_livraison", recu_le: "2026-10-19T09:00:00Z" })] });
  await page.waitForSelector(".lv-course", { timeout: 6000 }).catch(() => {});
  ok(await page.evaluate(() => !document.querySelector(".lv-recu") &&
    (document.querySelector(".lv-avancer") || {}).dataset.vers === "remise"),
    "en route : « Je l'ai remise »");
  await ctx.close();
}

titre("3. Une base d'avant : l'écran d'avant");
{
  const ancienne = course({ etat: "preparee" });
  delete ancienne.fiche; delete ancienne.recu_le;
  const { page, ctx, erreurs } = await ouvrirAdmin({ courses: [ancienne] });
  await page.waitForSelector(".lv-course", { timeout: 6000 }).catch(() => {});
  const t = plat(await page.evaluate(() => (document.querySelector(".lv-course") || {}).innerText || ""));
  ok(t.includes("À payer par MoMoPay : " + F(7000)) && /Afi/.test(t), "le montant et le client, comme avant");
  ok(await page.evaluate(() => !document.querySelector(".lv-recu") && !!document.querySelector(".lv-avancer")),
    "pas de « Reçu » que la base ne saurait pas traiter");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("5a. Les notifications de l'admin, sur plusieurs lignes");
{
  const { page, ctx, erreurs } = await ouvrirAdmin({ courses: [], hash: "#/notifications" });
  await page.waitForSelector(".notif-texte", { timeout: 6000 }).catch(() => {});
  const r = await page.evaluate(() => {
    const el = document.querySelector(".notif-texte");
    return el ? { ws: getComputedStyle(el).whiteSpace, h: el.getClientRects().length, texte: el.innerText } : null;
  });
  ok(r && r.ws === "pre-line" && /\n/.test(r.texte), "le retour à la ligne est rendu (" + (r && r.ws) + ")");
  ok(await page.evaluate(() => /Courses acceptées/.test(document.getElementById("vue").innerText)),
    "« Courses acceptées » : la famille a son nom");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("6a. Les demandes de course (admin)");
{
  const { page, ctx, erreurs, serveur } = await ouvrirAdmin({ courses: [], demandes: [DEMANDE] });
  await page.waitForSelector(".lv-demande", { timeout: 6000 }).catch(() => {});
  const t = plat(await page.evaluate(() => (document.querySelector(".lv-demande") || {}).innerText || ""));
  ok(/1 demande de course/i.test(plat(await page.evaluate(() => document.getElementById("vue").innerText))),
    "« 1 demande de course », en tête");
  ok(/Livraison groupée : 2 boutiques/.test(t), "« Livraison groupée : 2 boutiques »");
  ok(/Récupérer \(1\/2\)/i.test(t) && /Alpha/.test(t) && /Récupérer \(2\/2\)/i.test(t) && /Bêta/.test(t),
    "deux lieux où récupérer, numérotés");
  ok(t.includes("À payer par MoMoPay : " + F(5000)) && t.includes("Frais de livraison : " + F(2000)) &&
     t.includes("Déjà payé par le client : " + F(5000)), "les montants de toute la commande");
  ok(/Koffi/.test(t) && /Akpakpa/.test(t), "où livrer");
  /* (3.70.0) Une commande WhatsApp : où récupérer, tel que l'équipe l'a saisi. */
  const saisi = await page.evaluate(() => (document.querySelector(".lv-demande .lv-lieu-saisi") || {}).innerText || "");
  ok(/Où récupérer \(précisé par BIZZOO\)/i.test(saisi) && /marché Dantokpa, porte 3\s*\n\s*Appeler Rémi/.test(saisi),
    "le lieu saisi dans « Faire livrer », ligne à ligne (" + JSON.stringify(saisi) + ")");
  await page.click(".lv-prendre");
  await page.waitForTimeout(1500);
  const appel = serveur.appels.find((a) => a.fn === "prendre_course");
  ok(appel && appel.corps && appel.corps.commande === "cmd_g", "« Commande reçue » appelle prendre_course(cmd_g)");
  ok(await page.evaluate(() => !document.querySelector(".lv-demande") && !!document.querySelector(".lv-course")),
    "la demande devient sa course");
  const c = plat(await page.evaluate(() => (document.querySelector(".lv-course") || {}).innerText || ""));
  ok(/En préparation/.test(c) && /prépare le colis/.test(c) &&
     await page.evaluate(() => !document.querySelector(".lv-avancer") && !document.querySelector(".lv-recu")),
    "acceptée, colis pas prêt : « En préparation », pas encore « Je l'ai prise »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx } = await ouvrirAdmin({ courses: [], demandes: [DEMANDE], tropTard: true });
  await page.waitForSelector(".lv-prendre", { timeout: 6000 }).catch(() => {});
  await page.evaluate(() => { window.__t = []; const z = document.querySelector("#toasts") || document.body;
    new MutationObserver(() => window.__t.push(z.innerText)).observe(z, { childList: true, subtree: true }); });
  await page.click(".lv-prendre");
  await page.waitForTimeout(1500);
  ok(await page.evaluate(() => window.__t.some((x) => /Trop tard/.test(x))), "trop tard : on le lui dit");
  ok(await page.evaluate(() => !document.querySelector(".lv-demande")), "et la demande disparaît");
  await ctx.close();
}

/* ================================================================
   L'application client
   ================================================================ */
const MOI = "55550000-0000-0000-0000-000000000005";
const b64u = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");

async function ouvrirClient({ hash, courses = [], demandes = [] }) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2200 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(({ s }) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.setItem("bizzoo-session", JSON.stringify(s));
  }, { s: { access_token: b64u({ alg: "HS256" }) + "." + b64u({ sub: MOI, phone: "2290196777888", email: "" }) + ".s",
    refresh_token: "r", expire_a: Date.now() + 3600000, email: "", tel: "2290196777888" } });
  const serveur = { appels: [] };
  let liste = courses;
  let proposees = demandes;
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (r) => {
    const req = r.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) {
      serveur.appels.push({ fn: c.slice(4), corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })() });
    }
    if (c === "rpc/mon_compte_livreur") return d({ livreur: courses.length + demandes.length > 0, double: false });
    if (c === "rpc/courses_proposees") return d(proposees);
    if (c === "rpc/prendre_course") { proposees = []; return d(2); }
    if (c === "rpc/mes_livraisons") return d(liste);
    if (c === "rpc/accepter_course") {
      liste = liste.map((l) => ({ ...l, recu_le: "2026-10-19T09:00:00Z" }));
      return d(1);
    }
    if (c.startsWith("notifications")) return d(req.method() === "GET" ? [NOTIF] : []);
    if (c.startsWith("profils")) return d(courses.length ? [{ id: MOI }] : []);
    if (c.startsWith("clients")) return d([{ id: MOI, nom: "Afi", tel: "97666005", indicatif: "229",
      tel_verifie: true, type_compte: "client", revendeur_etat: "aucune", adresse: "Cotonou" }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html" + hash);
  await page.waitForTimeout(3000);
  return { page, ctx, erreurs, serveur };
}

titre("4 et 6b. L'application client renvoie le livreur vers BIZZOO Admin (3.66.0)");
{
  /* Ses courses, leurs demandes et leur sonnerie ne vivent plus que dans
     BIZZOO Admin (sections 1, 2 et 6a) : l'application client n'en
     montre plus aucune, et ne les touche pas. */
  const { page, ctx, erreurs, serveur } = await ouvrirClient({ hash: "#/mes-courses", courses: [course()],
    demandes: [DEMANDE] });
  const t = plat(await page.evaluate(() => document.getElementById("vue").innerText));
  ok(await page.evaluate(() => !!document.querySelector("#cp-espace-livreur")) && /BIZZOO Admin/.test(t),
    "« Mes courses » : le renvoi vers BIZZOO Admin");
  ok(await page.evaluate(() => !document.querySelector(".cp-course, .cp-demande")) && !/Demandes de course/.test(t),
    "aucune course ni demande listée dans l'application client");
  ok(!serveur.appels.some((a) => ["accepter_course", "prendre_course"].includes(a.fn)),
    "elle n'accepte ni ne prend aucune course");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("5b. Les notifications du client, sur plusieurs lignes");
{
  const { page, ctx, erreurs } = await ouvrirClient({ hash: "#/notifications" });
  await page.waitForSelector(".notif-texte", { timeout: 6000 }).catch(() => {});
  const r = await page.evaluate(() => {
    const el = document.querySelector(".notif-texte");
    return el ? { ws: getComputedStyle(el).whiteSpace, texte: el.innerText } : null;
  });
  ok(r && r.ws === "pre-line" && /\n/.test(r.texte), "le retour à la ligne est rendu (" + (r && r.ws) + ")");
  ok(await page.evaluate(() => /Votre livreur : Rachidi/.test(document.getElementById("vue").innerText) &&
    /\+229 0196777888/.test(document.getElementById("vue").innerText)),
    "« Votre livreur : Rachidi », et son numéro");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " ÉCHEC(S)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
