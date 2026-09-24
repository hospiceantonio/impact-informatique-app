/* =========================================================
   Les chemins par SMS, montrés seulement quand le SMS marche
   =========================================================
   LE DÉFAUT QU'ON DÉFEND ICI. En ligne, la connexion par téléphone
   n'est pas encore branchée chez Supabase : le fournisseur « Phone »
   est éteint. Pourtant « Entrer avec mon numéro », « Vérifier par
   SMS » et l'invitation à vérifier son numéro s'affichaient partout —
   et menaient tous au même refus, en anglais : « Unsupported phone
   provider ». Un client au Bénin, sans e-mail, restait là.

   Ce que le banc prouve :

     1. SMS FERMÉ : chacun de ces chemins se RETIRE — connexion,
        commande qui exige un compte, Mon compte, Mes commandes — et
        les autres portes restent ; un ancien lien vers « Entrer avec
        mon numéro » dit que ce n'est pas encore ouvert, et par où
        passer ;
     2. SMS OUVERT : tout est là, comme avant ;
     3. DANS LE DOUTE, ON MONTRE : Supabase injoignable, réponse
        illisible — les chemins restent, un refus clair vaut mieux
        qu'un chemin caché à tort ;
     4. UN REFUS EN ANGLAIS SE TRADUIT : si Supabase dit « ouvert » mais
        refuse l'envoi, le client lit une phrase française qui lui dit
        quoi faire — et les chemins se retirent ensuite ;
     5. LA QUESTION NE SE POSE QU'UNE FOIS par ouverture de
        l'application, quel que soit le nombre d'écrans.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-sms-ferme.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-sms-ferme.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const MOI = "44444444-4444-4444-4444-444444444444";
const BOU = [{ id: "bou_a", nom: "Impact Informatique", secteur: "Informatique", categorie_id: "cat_hightech",
  icone: "portable", couleur: "#0047D9", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }];
const PRODUIT = { id: "prod_1", code: "100061", nom: "Souris sans fil", reference: "SOU-1", prix: 7500,
  boutique_id: "bou_a", categorie_id: "cat_hightech", sous_categorie_id: null, stock: 5,
  disponible: true, sur_commande: false, images: [], video: "", en_avant: false,
  cree_le: "2026-09-01T10:00:00Z", modifie_le: "2026-09-01T10:00:00Z" };

/**
 * Une ouverture de l'application.
 *   sms       : true / false (ce que dit Supabase), "panne" (500), "muet" (réseau coupé)
 *   connecte  : un client connecté, au numéro NON vérifié
 *   otp       : ce que répond l'envoi du code
 */
async function ouvrir({ sms, connecte = false, otp = null, panier = false, locales = false } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1400 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(({ moi, connecte, panier, locales }) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
    if (connecte) {
      const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
        .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
      localStorage.setItem("bizzoo-session", JSON.stringify({
        access_token: b64({ alg: "HS256" }) + "." + b64({ sub: moi }) + ".s",
        refresh_token: "r", expire_a: Date.now() + 3600000, email: "awa@essai.bj" }));
    }
    if (panier) localStorage.setItem("bizzoo-panier", JSON.stringify([{ produitId: "prod_1", quantite: 1 }]));
    /* Une commande passée SANS compte, que la base n'attribue encore à
       personne : c'est elle qui fait naître l'invitation à vérifier. */
    if (locales) {
      localStorage.setItem("bizzoo-commandes", JSON.stringify([{ id: "cmd_locale", numero: "BZ-000900",
        total: 7500, devise: "FCFA", etat: "a_payer", cree_le: "2026-09-20T10:00:00Z",
        articles: [{ nom: "Souris sans fil", quantite: 1, prix: 7500 }], gardeeLe: Date.now() }]));
    }
  }, { moi: MOI, connecte, panier, locales });

  const reglages = [];
  const envois = [];
  await page.route("**/auth/v1/**", async (route) => {
    const req = route.request();
    const chemin = new URL(req.url()).pathname.replace(/^.*\/auth\/v1\//, "");
    if (chemin === "settings") {
      reglages.push(req.url());
      if (sms === "muet") return route.abort("failed");
      if (sms === "panne") return route.fulfill({ status: 500, body: "{}" });
      return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({
        external: { email: true, phone: sms === true, google: false },
        disable_signup: false, mailer_autoconfirm: false, phone_autoconfirm: false,
      }) });
    }
    if (chemin === "otp" || (chemin === "user" && req.method() === "PUT")) {
      envois.push(chemin);
      if (otp) return route.fulfill({ status: otp.status, contentType: "application/json", body: JSON.stringify(otp.corps) });
      return route.fulfill({ status: 200, contentType: "application/json", body: "{}" });
    }
    return route.fulfill({ status: 200, contentType: "application/json", body: "{}" });
  });
  await page.route("**/rest/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/produits_populaires")) return d([]);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: true }]);
    if (c.startsWith("clients")) return d([{ id: MOI, nom: "Awa", tel: "0197000011", indicatif: "229",
      tel_verifie: false, type_compte: "client", revendeur_etat: "aucune", adresse: "Cotonou" }]);
    if (c.startsWith("commandes") || c.startsWith("rpc/mes_commandes")) return d([]);
    if (c.startsWith("produits")) return d([PRODUIT]);
    if (c.startsWith("categories")) return d([]);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: false, fournisseur: "feexpay" }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  return { page, ctx, erreurs, reglages, envois };
}

const aller = async (page, hash, attente = 1300) => {
  await page.evaluate((h) => { location.hash = h; }, hash);
  await page.waitForTimeout(attente);
};
const texte = (page) => page.evaluate(() => document.querySelector("#vue, main, body").innerText);
const toast = (page) => page.evaluate(() =>
  [...document.querySelectorAll("#toasts .toast, .toast")].map((t) => t.textContent).join(" | "));

/* Ce que chaque écran montre des chemins par SMS. */
const chemins = (page) => page.evaluate(() => ({
  carteConnexion: [...document.querySelectorAll('a[href="#/connexion-tel"]')].length,
  verifier: !!document.querySelector("#cp-verifier"),
  pitchVerifie: /Un numéro vérifié vous rend/.test(document.body.innerText),
  orphelines: /sur ce téléphone seulement/.test(document.body.innerText),
  formulaireTel: !!document.querySelector("#cp-envoyer"),
  ferme: !!document.querySelector("#cp-sms-ferme"),
}));

titre("1. SMS fermé : les chemins par SMS se retirent");
{
  const { page, ctx, erreurs, reglages } = await ouvrir({ sms: false });
  await aller(page, "#/connexion");
  let c = await chemins(page);
  const t = await texte(page);
  ok(c.carteConnexion === 0 && !/Sans mot de passe/.test(t),
    "l'écran de connexion n'offre plus « Entrer avec mon numéro »");
  ok(/Se connecter/.test(t) && /Créer mon compte/.test(t) && /Mot de passe oublié/.test(t),
    "l'e-mail, la création de compte et le mot de passe oublié restent");

  await aller(page, "#/connexion-tel");
  c = await chemins(page);
  const t2 = await texte(page);
  ok(c.ferme && !c.formulaireTel, "un ancien lien vers « Entrer avec mon numéro » dit que ce n'est pas ouvert");
  ok(/pas encore\s+ouverts/.test(t2) && await page.$('#cp-sms-ferme a[href="#/connexion"]') &&
     await page.$('#cp-sms-ferme a[href="#/inscription"]'),
    "et montre les deux autres portes : se connecter, créer son compte");
  ok(reglages.length === 1, "Supabase n'a été interrogé qu'une fois pour deux écrans (" + reglages.length + ")");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("1 bis. SMS fermé : la commande qui exige un compte");
{
  const { page, ctx, erreurs } = await ouvrir({ sms: false, panier: true });
  await aller(page, "#/commande", 2200);
  const c = await chemins(page);
  const t = await texte(page);
  ok(/Un compte pour commander/.test(t), "l'écran invite bien à ouvrir un compte");
  ok(c.carteConnexion === 0, "sans « Entrer avec mon numéro »");
  ok(!!(await page.$('a[href="#/inscription"][data-vers-compte]')) &&
     !!(await page.$('a[href="#/connexion"][data-vers-compte]')),
    "« Créer mon compte » et « Se connecter » restent, et ramènent à la commande");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("1 ter. SMS fermé : Mon compte et Mes commandes, numéro non vérifié");
{
  const { page, ctx, erreurs } = await ouvrir({ sms: false, connecte: true, locales: true });
  await aller(page, "#/compte", 1800);
  let c = await chemins(page);
  ok(!c.verifier && !c.pitchVerifie, "Mon compte n'offre plus « Vérifier par SMS », ni la phrase qui y invite");
  ok(!!(await page.$("#cp-tel")) && !!(await page.$("#cp-enregistrer")),
    "le numéro se saisit et s'enregistre toujours");
  await aller(page, "#/mes-commandes", 1800);
  c = await chemins(page);
  const t = await texte(page);
  ok(/BZ-000900/.test(t), "la commande gardée sur ce téléphone s'affiche");
  ok(!c.orphelines, "sans l'invitation à vérifier un numéro qu'on ne peut pas vérifier");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("2. SMS ouvert : tout est là, comme avant");
{
  const { page, ctx, erreurs } = await ouvrir({ sms: true, connecte: false });
  await aller(page, "#/connexion");
  let c = await chemins(page);
  ok(c.carteConnexion === 1, "« Entrer avec mon numéro » sur l'écran de connexion");
  await aller(page, "#/connexion-tel");
  c = await chemins(page);
  ok(c.formulaireTel && !c.ferme, "le formulaire du numéro");
  await ctx.close();

  const second = await ouvrir({ sms: true, connecte: true, locales: true });
  await aller(second.page, "#/compte", 1800);
  c = await chemins(second.page);
  ok(c.verifier && c.pitchVerifie, "« Vérifier par SMS » dans Mon compte");
  await aller(second.page, "#/mes-commandes", 1800);
  c = await chemins(second.page);
  ok(c.orphelines, "l'invitation à vérifier dans Mes commandes");
  ok(!erreurs.length && !second.erreurs.length, "aucune erreur dans la page");
  await second.ctx.close();

  const troisieme = await ouvrir({ sms: true, panier: true });
  await aller(troisieme.page, "#/commande", 2200);
  c = await chemins(troisieme.page);
  ok(c.carteConnexion === 1, "« Entrer avec mon numéro » quand la commande exige un compte");
  await troisieme.ctx.close();
}

titre("3. Dans le doute, on montre");
for (const cas of ["panne", "muet"]) {
  const { page, ctx, erreurs } = await ouvrir({ sms: cas, connecte: true });
  await aller(page, "#/compte", 1800);
  const c = await chemins(page);
  ok(c.verifier, (cas === "panne" ? "Supabase répond mal" : "réseau coupé") +
    " : « Vérifier par SMS » reste");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("4. Un refus en anglais se traduit");
{
  const { page, ctx, erreurs, envois } = await ouvrir({ sms: true,
    otp: { status: 400, corps: { code: 400, error_code: "phone_provider_disabled", msg: "Unsupported phone provider" } } });
  await aller(page, "#/connexion-tel");
  await page.fill("#cp-tel", "0197121596");
  await page.click("#cp-envoyer");
  await page.waitForTimeout(900);
  const t = await toast(page);
  ok(envois.length === 1, "la demande de code est partie");
  ok(/pas encore ouverts/.test(t) && /e-mail et votre mot de passe/.test(t) && !/Unsupported/i.test(t),
    "le client lit une phrase française qui dit quoi faire (« " + t.slice(0, 70) + "… »)");
  await aller(page, "#/connexion");
  const c = await chemins(page);
  ok(c.carteConnexion === 0, "et la carte « Entrer avec mon numéro » se retire ensuite");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("4 bis. Le même refus, depuis Mon compte");
{
  const { page, ctx, envois } = await ouvrir({ sms: true, connecte: true,
    otp: { status: 422, corps: { code: 422, error_code: "phone_provider_disabled", msg: "Unsupported phone provider" } } });
  await aller(page, "#/compte", 1800);
  await page.click("#cp-verifier");
  await page.waitForTimeout(900);
  const t = await toast(page);
  ok(envois.includes("user"), "la vérification a été demandée");
  ok(/pas encore ouverts/.test(t) && !/Unsupported/i.test(t), "le refus se lit en français");
  ok(await page.evaluate(() => { const b = document.querySelector("#cp-verifier"); return !!b && !b.disabled; }),
    "le bouton revient : rien n'est bloqué");
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec." : "\nTous les constats sont bons.");
process.exit(echecs ? 1 : 0);
