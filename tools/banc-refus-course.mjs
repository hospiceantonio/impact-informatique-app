/* =========================================================
   Le livreur refuse ; la boutique voit qui livre (3.59.0)
   =========================================================
   La base est éprouvée par supabase/tests/99zzzzzzzzzzzz-refus-course.sql.
   Ce banc regarde les écrans :

     1. LA BOUTIQUE, sur chaque commande payée : « Prise par Kodjo » et
        son numéro, « Confiée à … — en attente de sa réponse », « Commande
        refusée par le livreur » avec le motif — et alors « Confier à
        nouveau » —, ou « En attente d'un livreur » ;
     2. LE LIVREUR : « Refuser la course » tant que le colis n'est pas
        parti ; la feuille demande pourquoi ; « refuser_course » part
        avec la commande et le motif ; colis parti : plus de bouton ;
     3. une notification mise de côté (« …_avant_<n> ») garde sa famille.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-refus-course.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const plat = (s) => s.replace(/[  ]/g, " ").replace(/\s+/g, " ");

const PORTEUR = "cccccccc-1111-1111-1111-111111111111";
const CHEF = "22222222-2222-2222-2222-222222222222";
const PROFILS = {
  [PORTEUR]: { id: PORTEUR, email: "porteur@alpha.bj", nom: "Kodjo", role: "livreur", actif: true,
    peut_modifier_produits: true, boutique_id: "bou_a" },
  [CHEF]: { id: CHEF, email: "chef@alpha.bj", nom: "Chef", role: "administrateur", actif: true,
    peut_modifier_produits: true, boutique_id: "bou_a" },
};
const commande = (id, numero, etat = "preparee") => ({ id, numero, client_nom: "Afi", client_tel: "0197000000",
  client_indicatif: "229", client_adresse: "Cotonou", note: "", total: 10000, devise: "FCFA",
  etat: "payee", transaction_id: "t1", fournisseur_ref: "ref_1", confirme_par: "", remarque: "",
  transaction_annoncee: "", revendeur: false, paye_le: "2026-10-20T09:02:00Z",
  cree_le: "2026-10-20T09:00:00Z", taux_acompte: 30, acompte: 3000, verse: 3000,
  restes: { reste: 7000, boutiques: { bou_a: 7000 } },
  commande_lignes: [{ id: "lig_" + id, commande_id: id, boutique_id: "bou_a", produit_id: "prod_1",
    nom: "Casque", code: "0001", reference: "", prix: 9000, quantite: 1, etat, confirme_le: null }] });
const COMMANDES = [commande("c1", "BZ-000101"), commande("c2", "BZ-000102"),
  commande("c3", "BZ-000103"), commande("c4", "BZ-000104", "nouvelle")];
const LIVRAISONS = [
  { commande_id: "c1", boutique_id: "bou_a", livreur_nom: "Kodjo", livreur_tel: "0196200001",
    livreur_bizzoo: false, recu_le: "2026-10-20T09:10:00Z", refus_nom: "", refus_motif: "", refuse_le: null },
  { commande_id: "c2", boutique_id: "bou_a", livreur_nom: "Nadia", livreur_tel: "0196200002",
    livreur_bizzoo: true, recu_le: null, refus_nom: "", refus_motif: "", refuse_le: null },
  { commande_id: "c3", boutique_id: "bou_a", livreur_nom: "", livreur_tel: "", livreur_bizzoo: false,
    recu_le: null, refus_nom: "Moussa", refus_motif: "Ma moto est en panne", refuse_le: "2026-10-20T09:20:00Z" },
  { commande_id: "c4", boutique_id: "bou_a", livreur_nom: "", livreur_tel: "", livreur_bizzoo: false,
    recu_le: null, refus_nom: "", refus_motif: "", refuse_le: null },
];
const fiche = { numero: "BZ-000101",
  retrait: { boutique: "Alpha", adresse: "Ganhi", tel: "0197111222", indicatif: "229" },
  livraison: { nom: "Afi", adresse: "Fidjrossè", note: "", tel: "97666007", indicatif: "229" },
  devise: "FCFA", frais: 1000, deja_paye: 3000, a_encaisser: 7000, encaisse: null };
const course = (o = {}) => ({ commande_id: "c1", numero: "BZ-000101", boutique_id: "bou_a",
  nom_boutique: "Alpha", client_nom: "Afi", client_tel: "97666007", client_indicatif: "229",
  client_adresse: "Fidjrossè", note: "", etat: "preparee", articles: [{ nom: "Casque", quantite: 1 }],
  paye_le: "2026-10-20T08:00:00Z", a_encaisser: 7000, fiche, recu_le: "2026-10-20T08:05:00Z", ...o });

async function ouvrirAdmin({ moi, hash, courses = [], notifs = [] }) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2400 }, serviceWorkers: "block" });
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
  }, { moi, email: PROFILS[moi].email });
  const serveur = { appels: [] };
  let liste = courses;
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) {
      serveur.appels.push({ fn: c.slice(4), corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })() });
    }
    if (c.startsWith("profils")) {
      const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      return d(id ? [PROFILS[id]].filter(Boolean) : Object.values(PROFILS));
    }
    if (c.startsWith("positions_livreurs")) return d([{ profil_id: PORTEUR, latitude: 6.37,
      longitude: 2.42, adresse: "Cadjèhoun" }]);
    if (c === "rpc/mes_livraisons") return d(liste);
    if (c === "rpc/refuser_course") { liste = []; return d(1); }
    if (c === "rpc/livraison_des_commandes") return d(LIVRAISONS);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("notifications")) return d(notifs);
    if (c.startsWith("commandes")) {
      if (/commande_lignes\(etat\)/.test(u.searchParams.get("select") || "")) return d([]);
      return d(COMMANDES);
    }
    if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech",
      icone: "magasin", couleur: "#0047D9", devise: "FCFA", indicatif: "229", whatsapp: "97000001",
      actif: true, ordre: 1 }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  if (hash) {
    await page.evaluate((h) => { location.hash = h; }, hash);
    await page.waitForTimeout(1800);
  }
  return { page, ctx, erreurs, serveur };
}
const carte = (page, id) => page.evaluate((id) => {
  const c = document.querySelector('.cmd-carte[data-commande="' + id + '"]');
  if (!c) return { texte: "", confier: "" };
  const z = c.querySelector("[data-livraison-pour]");
  const b = c.querySelector("[data-confier]");
  return { texte: z && !z.hidden ? z.innerText : "", confier: b ? b.innerText : "",
           tel: !!c.querySelector('.cmd-livraison a[href^="tel:"]') };
}, id);

titre("1. La boutique voit qui livre");
{
  const { page, ctx, erreurs, serveur } = await ouvrirAdmin({ moi: CHEF, hash: "#/commandes" });
  await page.waitForSelector(".cmd-livraison:not([hidden])", { timeout: 6000 }).catch(() => {});
  const c1 = await carte(page, "c1"), c2 = await carte(page, "c2"),
        c3 = await carte(page, "c3"), c4 = await carte(page, "c4");
  ok(/Prise par Kodjo/.test(plat(c1.texte)) && /0196200001/.test(c1.texte) && c1.tel,
    "« Prise par Kodjo », et son numéro à appeler");
  ok(/Confiée à Nadia/.test(plat(c2.texte)) && /BIZZOO/.test(c2.texte) && /en attente de sa réponse/.test(plat(c2.texte)),
    "« Confiée à Nadia (BIZZOO) — en attente de sa réponse »");
  ok(/Commande refusée par le livreur/.test(plat(c3.texte)) && /Moussa : « Ma moto est en panne »/.test(plat(c3.texte)),
    "« Commande refusée par le livreur » — Moussa, et son motif");
  ok(/Confier à nouveau/.test(c3.confier), "et le bouton devient « Confier à nouveau »");
  ok(/Confier à un livreur/.test(c1.confier), "ailleurs, « Confier à un livreur » reste");
  ok(/En attente d'un livreur/.test(plat(c4.texte)), "sans livreur ni refus : « En attente d'un livreur »");
  const appel = serveur.appels.find((a) => a.fn === "livraison_des_commandes");
  ok(appel && ["c1", "c2", "c3", "c4"].every((i) => appel.corps.cibles.includes(i)),
    "une seule question à la base, pour toutes les commandes payées");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("2. Le livreur refuse la course");
{
  const { page, ctx, erreurs, serveur } = await ouvrirAdmin({ moi: PORTEUR, courses: [course()] });
  await page.waitForSelector(".lv-course", { timeout: 6000 }).catch(() => {});
  ok(await page.evaluate(() => !!document.querySelector(".lv-refuser")), "« Refuser la course » tant que le colis n'est pas parti");
  await page.click(".lv-refuser");
  await page.waitForTimeout(400);
  await page.fill("#saisie-motif", "Je suis malade");
  await page.click('[data-role="ok"]');
  await page.waitForTimeout(1500);
  const appel = serveur.appels.find((a) => a.fn === "refuser_course");
  ok(appel && appel.corps.commande === "c1" && appel.corps.motif === "Je suis malade",
    "refuser_course(c1, « Je suis malade »)");
  ok(await page.evaluate(() => !document.querySelector(".lv-course")), "la course quitte sa liste");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx, serveur } = await ouvrirAdmin({ moi: PORTEUR, courses: [course()] });
  await page.waitForSelector(".lv-refuser", { timeout: 6000 }).catch(() => {});
  await page.click(".lv-refuser");
  await page.waitForTimeout(400);
  await page.click('[data-role="annuler"]').catch(() => {});
  await page.waitForTimeout(600);
  ok(!serveur.appels.some((a) => a.fn === "refuser_course"), "« Annuler » : rien ne part");
  await ctx.close();
}
{
  const { page, ctx } = await ouvrirAdmin({ moi: PORTEUR, courses: [course({ etat: "en_livraison" })] });
  await page.waitForSelector(".lv-course", { timeout: 6000 }).catch(() => {});
  ok(await page.evaluate(() => !document.querySelector(".lv-refuser")), "colis parti : plus de « Refuser »");
  await ctx.close();
}

titre("3. Une nouvelle mise de côté garde sa famille");
{
  const notifs = [{ id: 7, destinataire: CHEF, type: "course_acceptee_avant_42", commande_id: "c1",
    titre: "Course acceptée par Moussa", corps: "Commande BZ-000101.", lien: "#/commandes/c1",
    lue_le: null, cree_le: new Date().toISOString() }];
  const { page, ctx, erreurs } = await ouvrirAdmin({ moi: CHEF, hash: "#/notifications", notifs });
  await page.waitForSelector(".notif", { timeout: 6000 }).catch(() => {});
  const t = await page.evaluate(() => document.getElementById("vue").innerText);
  ok(/Courses acceptées/.test(t) && !/Autres/.test(t), "« Courses acceptées », pas « Autres »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " ÉCHEC(S)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
