/* =========================================================
   Banc — le client prévenu à chaque étape (3.70.0)

   La base décide qui reçoit quoi (supabase/tests/99zzz…-sms-clients.sql).
   Ce banc regarde les deux écrans :

     1. BIZZOO Admin → Réglages (superadministrateur) : la carte « SMS aux
        clients » dit l'état du jour, et « Enregistrer » envoie à la base
        l'interrupteur, les étapes cochées, les cibles et les plafonds ;
        une base d'avant le dit sans casser l'écran ;
     2. BIZZOO Personnel → Suivi des commandes → SMS : les SMS partis, les
        refusés, le crédit épuisé en rouge, les échecs avec leur commande
        — et aucun numéro de client.

   La base est simulée : seules les réponses de Supabase sont jouées.

     PLAYWRIGHT=… CHROMIUM=… BANC_URL=http://127.0.0.1:5191 node tools/banc-sms-clients.mjs
     CAPTURES=<dossier> : une image de chaque écran.
   ========================================================= */
const { chromium } = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default;
const BASE = process.env.BANC_URL || "http://127.0.0.1:5191";
const EXE = process.env.CHROMIUM || undefined;
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const plat = (s) => String(s || "").replace(/\s+/g, " ").trim();
const nav = await chromium.launch(EXE ? { executablePath: EXE, args: ["--no-sandbox"] } : { args: ["--no-sandbox"] });

/* ---------------- 1. BIZZOO Admin ---------------- */
const SUPER = "11111111-1111-1111-1111-111111111111";
const PROFIL = { id: SUPER, email: "chef@bizzoo.bj", nom: "Super", role: "superadministrateur", actif: true,
  boutique_id: null, peut_commandes: true, peut_modifier_produits: true };
const REGLAGE = { actif: false, plafond: 3, plafond_jour: 300, etapes: ["commande_payee", "course_acceptee", "commande_remise"],
  sans_compte: true, whatsapp: true, sans_appareil: true, actif_depuis: null, branche: true,
  aujourdhui: { envoyes: 0, en_attente: 0, refuses: 0 }, dernier_refus: null };

async function ouvrirAdmin({ baseAncienne = false } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2600 }, serviceWorkers: "block" });
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
  }, { moi: SUPER, email: PROFIL.email });
  const serveur = { appels: [] };
  let reglage = { ...REGLAGE };
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, statut = 200) => route.fulfill({ status: statut, contentType: "application/json", body: JSON.stringify(x) });
    const corps = (() => { try { return req.postDataJSON(); } catch (_) { return null; } })();
    if (c.startsWith("rpc/")) {
      const fn = c.slice(4);
      serveur.appels.push({ fn, corps });
      if (fn === "etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
      if (fn === "sms_commandes_reglages") {
        if (baseAncienne) return d({ code: "PGRST202", message: "Could not find the function public.sms_commandes_reglages without parameters in the schema cache" }, 404);
        return d(reglage);
      }
      if (fn === "regler_sms_commandes") {
        reglage = { ...reglage, ...corps, actif_depuis: corps.actif ? "2026-10-28T10:00:00Z" : reglage.actif_depuis };
        return d(reglage);
      }
      return d(null);
    }
    if (req.method() !== "GET") return route.fulfill({ status: 204, body: "" });
    if (c.startsWith("profils")) return d([PROFIL]);
    if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  await page.evaluate(() => { location.hash = "#/reglages"; });
  await page.waitForTimeout(1600);
  if (await page.$('[data-cible="enseigne"]')) {
    await page.click('[data-cible="enseigne"]');
    await page.waitForTimeout(1200);
  }
  return { page, ctx, erreurs, serveur };
}

titre("1. BIZZOO Admin : la carte « SMS aux clients »");
{
  const { page, ctx, erreurs, serveur } = await ouvrirAdmin();
  await page.waitForSelector("#smsc-enregistrer", { timeout: 6000 }).catch(() => {});
  const carte = plat(await page.evaluate(() => (document.querySelector("#section-sms-clients") || {}).textContent || ""));
  ok(/SMS aux clients/.test(carte) && /Coupés : aucun SMS ne part/.test(carte), "la carte dit que les SMS sont coupés");
  ok(await page.$eval("#smsc-commande_payee", (e) => e.checked) && await page.$eval("#smsc-course_acceptee", (e) => e.checked)
    && !(await page.$eval("#smsc-commande_en_livraison", (e) => e.checked)), "les étapes en place sont cochées");
  if (process.env.CAPTURES) await (await page.$("#section-sms-clients")).screenshot({ path: process.env.CAPTURES + "/admin-sms-clients.png" });
  await page.click("label[for=smsc-actif]");
  await page.click("label[for=smsc-commande_en_livraison]");
  await page.click("label[for=smsc-commande_remise]");
  await page.click("label[for=smsc-whatsapp]");
  await page.fill("#smsc-plafond", "2");
  await page.fill("#smsc-plafond-jour", "150");
  await page.click("#smsc-enregistrer");
  await page.waitForTimeout(800);
  const envoi = serveur.appels.filter((a) => a.fn === "regler_sms_commandes").pop();
  ok(envoi && envoi.corps.actif === true, "« Enregistrer » allume les SMS");
  ok(envoi && JSON.stringify(envoi.corps.etapes) === JSON.stringify(["commande_payee", "course_acceptee", "commande_en_livraison"]),
    "avec les étapes cochées (" + (envoi && envoi.corps.etapes) + ")");
  ok(envoi && envoi.corps.sans_compte === true && envoi.corps.whatsapp === false && envoi.corps.sans_appareil === true,
    "et les cibles choisies");
  ok(envoi && envoi.corps.plafond === 2 && envoi.corps.plafond_jour === 150, "et les plafonds saisis");
  const apres = plat(await page.evaluate(() => (document.querySelector("#section-sms-clients") || {}).textContent || ""));
  ok(/Allumés depuis/.test(apres), "la carte, relue, dit « Allumés »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx, erreurs } = await ouvrirAdmin({ baseAncienne: true });
  await page.waitForTimeout(800);
  const carte = plat(await page.evaluate(() => (document.querySelector("#section-sms-clients") || {}).textContent || ""));
  ok(/sms-clients\.sql/.test(carte), "une base d'avant : la carte dit quel fichier exécuter");
  ok(!erreurs.length, "et l'écran ne casse pas");
  await ctx.close();
}

/* ---------------- 2. BIZZOO Personnel ---------------- */
titre("2. BIZZOO Personnel : Suivi → SMS");
{
  const COMPTEUR = {
    periode: { depuis: "2026-09-29", jusqu: "2026-10-28" },
    reglages: { actif: true, plafond: 3, plafond_jour: 300, etapes: ["commande_payee", "course_acceptee"], actif_depuis: "2026-10-28T08:00:00Z" },
    total: { envoyes: 42, refuses: 3, en_attente: 1, abandonnes: 2, plafonnes: 2, commandes: 17, credit_epuise: 3 },
    par_jour: [{ jour: "2026-10-28", envoyes: 30, refuses: 3, autres: 2 }, { jour: "2026-10-27", envoyes: 12, refuses: 0, autres: 1 }],
    par_etape: [{ etape: "course_acceptee", envoyes: 20, total: 22 }, { etape: "commande_payee", envoyes: 22, total: 25 }],
    echecs: [{ le: "2026-10-28T09:00:00Z", etape: "course_acceptee", etat: "refuse", code: "INSUFFICIENT_BALANCE",
      message: "Crédit SMS épuisé : rechargez le compte CREATISINTER.", commande_id: "cmd_1", numero: "BZ-0101" }],
  };
  const ctx = await nav.newContext({ viewport: { width: 1280, height: 1400 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(() => {
    localStorage.setItem("bizzoo-personnel-session", JSON.stringify({ access_token: "jeton", refresh_token: "r",
      email: "awa@essai.bj", expire_a: Date.now() + 3600 * 1000 }));
  });
  const REPONSES = {
    etat_connexion: { equipe: false },
    rh_tableau_de_bord: { moi: { id: "e1", prenoms: "Awa", nom: "Essai", administration: true, profil: "Administrateur" } },
    rh_caisse_acces: null, rh_compteurs_solde: {}, rh_mes_menus: ["suivi"], rh_suivi_alertes_nb: 0, rh_incidents_ouverts_nb: 0,
    rh_activation: null, rh_paie_a_jour: 0, rh_sms_compteur: COMPTEUR,
  };
  await page.route(/supabase\.co\//, async (route) => {
    const nom = (new URL(route.request().url()).pathname.match(/\/rest\/v1\/rpc\/([a-z_0-9]+)/) || [])[1];
    const r = nom && nom in REPONSES ? REPONSES[nom] : (nom ? null : []);
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(r) });
  });
  await page.goto(BASE + "/personnel/#/suivi/sms");
  await page.waitForFunction(() => document.body.innerText.includes("SMS envoyés"), null, { timeout: 15000 });
  const t = plat(await page.evaluate(() => document.body.innerText));
  ok(/42 SMS envoyés/.test(t) && /17 commandes prévenues/.test(t), "les SMS envoyés et les commandes prévenues");
  ok(/3 refusés par la passerelle/.test(t) && /2 retenus par un plafond/.test(t), "les refus et les plafonds");
  ok(/Crédit SMS épuisé : 3 SMS refusé/.test(t), "le crédit épuisé est dit en clair, avec quoi faire");
  ok(/Livreur trouvé/.test(t) && /Commande BZ-0101/.test(t), "les échecs, avec leur étape et leur commande");
  ok(await page.$('a[href="#/suivi/commande/cmd_1"]') !== null, "un lien mène à la fiche de la commande");
  ok(/SMS allumés depuis/.test(t), "l'état du réglage, et où le changer");
  ok(!/\d{8,}/.test(t.replace(/2026|BZ-\d+/g, "")), "aucun numéro de téléphone à l'écran");
  ok(await page.$$eval(".filtres button", (b) => b.some((x) => x.textContent === "SMS" && x.classList.contains("actif"))),
    "l'onglet « SMS » du suivi est actif");
  if (process.env.CAPTURES) await page.screenshot({ path: process.env.CAPTURES + "/personnel-sms.png" });
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " échec(s)" : "\nTout passe.");
process.exit(echecs ? 1 : 0);
