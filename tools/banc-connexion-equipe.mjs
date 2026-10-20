/* =========================================================
   L'équipe entre avec un code reçu par SMS (3.58.0)
   =========================================================
   CE QUE LE BANC GARDE, dans l'application admin. La base, elle, est
   éprouvée par supabase/tests/99u-connexion-sms.sql : ici, c'est la
   PORTE qu'on regarde — ce que voit la personne qui entre.

     1. LE CODE AVANT TOUT : l'enseigne l'exige, la session n'est pas
        confirmée — l'application ne charge rien et demande le code ;
        il part par la fonction Edge, avec le jeton du compte et rien
        d'autre ; six chiffres, ni plus ni moins ; un code faux dit
        combien d'essais restent ; le bon ouvre l'application, et
        l'entrée se journalise ;
     2. LES REFUS SE LISENT : « trop tôt » montre la saisie et fait
        patienter le renvoi ; un compte sans numéro est prévenu au lieu
        d'attendre un code qui ne partira nulle part ;
     3. RIEN N'EST EXIGÉ, OU BASE D'AVANT : l'application s'ouvre comme
        avant ;
     4. LES RÉGLAGES : la carte compte l'équipe, nomme qui n'a pas de
        numéro ; l'interrupteur reste fermé tant que le superadmin n'a
        pas reçu et rendu son propre code ; allumer demande confirmation,
        et « Annuler » n'envoie rien ;
     5. LES COMPTES disent qui les a créés, quand, et l'état de leur
        numéro ; un nouveau compte ne se crée plus sans numéro ;
     6. LES CLIENTS disent par quelle porte ils sont entrés.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-connexion-equipe.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-connexion-equipe.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const SUPER = "ffff0000-0000-4000-8000-000000000006";
const CHEF = "aaaa0000-0000-4000-8000-000000000001";
const MODO = "bbbb0000-0000-4000-8000-000000000002";
const LIVREUR = "cccc0000-0000-4000-8000-000000000003";
const SESSION = "e1000000-0000-4000-8000-000000000001";

const BOU = [{ id: "bou_tech", nom: "IMPACT", secteur: "Informatique", categorie_id: "cat_h",
  icone: "portable", couleur: "#2550B7", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }];

const profil = (id, role, reste) => ({
  id, email: id.slice(0, 4) + "@bizzoo.bj", nom: "", tel: "", role, actif: true,
  peut_modifier_produits: true, boutique_id: role === "superadministrateur" ? null : "bou_tech",
  peut_commandes: true, peut_boutiques: false, peut_finances: false,
  cree_le: "2026-10-10T13:05:00Z", ...(reste || {}),
});

/* L'équipe que « Comptes » et les Réglages lisent. */
const EQUIPE = [
  profil(SUPER, "superadministrateur", { nom: "Sena", tel: "0197121596" }),
  profil(CHEF, "administrateur", { nom: "Rohim", tel: "0161000001", tel_verifie: true,
    cree_par: SUPER, cree_par_nom: "Sena (superadministrateur)", cree_le: "2026-10-10T13:05:00Z" }),
  profil(MODO, "moderateur", { nom: "Awa", tel: "", cree_par: CHEF,
    cree_par_nom: "Rohim (administrateur)", cree_le: "2026-10-11T08:30:00Z" }),
  profil(LIVREUR, "livreur", { nom: "Koffi", tel: "0190000003", actif: false,
    cree_le: "2026-09-01T07:00:00Z" }),
];

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64")
  .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

/**
 * L'application admin, ouverte au nom d'un compte.
 *   etat     : ce que rend « etat_connexion » — null : base d'avant (404)
 *   edge     : les réponses successives de la fonction « code-connexion »
 *   codes    : les réponses successives de « confirmer_code_connexion »
 *   clients  : ce que rend « clients_liste »
 */
async function ouvrir(o) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1900 },
    timezoneId: "Africa/Porto-Novo", serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  const moi = o.moi || EQUIPE[0];
  const jeton = b64({ alg: "HS256" }) + "." + b64({ sub: moi.id, session_id: SESSION }) + ".s";
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "cle-de-banc" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: a.jeton, refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
    if (a.appareil) localStorage.setItem("bizzoo-appareil-confiance", a.appareil);
    window.__toasts = [];
    document.addEventListener("DOMContentLoaded", () => {
      const zone = document.querySelector("#toasts");
      if (!zone) return;
      new MutationObserver(() => {
        for (const t of zone.querySelectorAll(".toast")) {
          if (!t.__vu) { t.__vu = true; window.__toasts.push(t.textContent); }
        }
      }).observe(zone, { childList: true });
    });
  }, { jeton, email: moi.email, appareil: o.appareil || "" });

  const note = { edge: [], codes: [], regler: [], journal: [], lectures: [], signup: [],
                 confier: [], reconnaitre: [] };
  let etat = o.etat === undefined ? null : { ...o.etat };
  const edge = [...(o.edge || [])];
  const codes = [...(o.codes || [])];

  await page.route("**/auth/v1/**", (route) => {
    const req = route.request();
    if (/\/signup$/.test(new URL(req.url()).pathname)) {
      note.signup.push(JSON.parse(req.postData() || "{}"));
      return route.fulfill({ status: 200, contentType: "application/json",
        body: JSON.stringify({ id: "nouveau", email: "nouveau@bizzoo.bj" }) });
    }
    return route.fulfill({ status: 200, contentType: "application/json", body: "{}" });
  });
  await page.route("**/functions/v1/**", (route) => {
    const req = route.request();
    note.edge.push({ nom: new URL(req.url()).pathname.split("/").pop(),
      auth: req.headers()["authorization"] || "", corps: req.postData() || "" });
    const r = edge.shift() || { statut: 200, corps: { ok: true, fin_numero: "96" } };
    return route.fulfill({ status: r.statut || 200, contentType: "application/json", body: JSON.stringify(r.corps) });
  });
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (req.method() === "GET") note.lectures.push(c + u.search);
    if (c === "rpc/etat_connexion") {
      if (!etat) return route.fulfill({ status: 404, contentType: "application/json",
        body: JSON.stringify({ code: "PGRST202", message: "Could not find the function public.etat_connexion without parameters in the schema cache" }) });
      return d(etat);
    }
    if (c === "rpc/confirmer_code_connexion") {
      note.codes.push(JSON.parse(req.postData() || "{}"));
      const r = codes.shift() || { ok: false, raison: "sans_code" };
      if (r.ok && etat) etat = { ...etat, session_confirmee: true, tel_verifie: true };
      return d(r);
    }
    if (c === "rpc/regler_sms_equipe") {
      const corps = JSON.parse(req.postData() || "{}");
      note.regler.push(corps);
      if (etat) etat = { ...etat, sms_exige: !!corps.exige };
      return d(!!corps.exige);
    }
    /* L'appareil de confiance (3.59.0). */
    if (c === "rpc/reconnaitre_appareil") {
      note.reconnaitre.push(JSON.parse(req.postData() || "{}"));
      if (o.reconnu && etat) etat = { ...etat, session_confirmee: true };
      return d(!!o.reconnu);
    }
    if (c === "rpc/confier_appareil") {
      note.confier.push(JSON.parse(req.postData() || "{}"));
      return d(new Date(Date.now() + 30 * 86400000).toISOString());
    }
    if (c === "rpc/clients_liste") return d(o.clients || []);
    if (c === "rpc/client_commandes") return d([]);
    if (c.startsWith("rpc/")) return d(null);
    if (c === "journal" && req.method() === "POST") {
      note.journal.push(JSON.parse(req.postData() || "{}"));
      return route.fulfill({ status: 201, body: "" });
    }
    if (req.method() !== "GET") return route.fulfill({ status: 204, body: "" });
    if (c.startsWith("profils")) {
      if (/id=eq\./.test(u.search)) return d([moi]);
      /* « Votre propre compte n'apparaît pas » : la liste écarte le sien. */
      return d(EQUIPE);
    }
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html" + (o.hash || ""), { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(o.attente || 2400);
  return { page, ctx, erreurs, note };
}

const toasts = (page) => page.evaluate(() => (window.__toasts || []).join(" | "));
const texteVue = (page) => page.evaluate(() => document.querySelector("#vue").innerText);
const etatCode = (page, racine) => page.evaluate((r) =>
  ((document.querySelector((r || "") + " #code-etat") || {}).textContent || ""), racine || "");
const barre = (page) => page.evaluate(() => {
  const b = document.querySelector("#tabbar");
  return !!b && getComputedStyle(b).display !== "none" && b.getBoundingClientRect().height > 0;
});
const sansErreur = (erreurs) => ok(!erreurs.length, "aucune erreur dans la page" +
  (erreurs.length ? " : " + erreurs[0] : ""));
const lecturesCatalogue = (note) => note.lectures.filter((l) =>
  /^(produits|commandes|notifications|categories)/.test(l)).length;

const EXIGE = { equipe: true, sms_exige: true, session_confirmee: false, numero: true,
  fin_numero: "01", tel_verifie: false };

titre("1. Le code avant tout");
{
  const chef = EQUIPE[1];
  const { page, ctx, erreurs, note } = await ouvrir({ moi: chef, etat: EXIGE,
    codes: [{ ok: false, raison: "code_faux", restants: 4 }, { ok: true }] });
  const t = await texteVue(page);
  ok(/Confirmez votre connexion/.test(t) && /finit par\s+01/.test(t),
    "l'application demande le code, et dit où il part (…01)");
  ok(!(await barre(page)), "la barre du bas est cachée : rien d'autre n'est ouvert");
  /* AUCUNE lecture, pas seulement celles du catalogue : sans code, la base
     ne rendrait rien — et un écran chargé à vide ne dirait pas pourquoi. */
  ok(note.lectures.length === 0, "rien n'est lu avant le code (" +
    (note.lectures.length ? note.lectures.slice(0, 3).join(", ") : "0 lecture") + ")");

  await page.click("#code-demander");
  await page.waitForTimeout(700);
  const appel = note.edge[0] || {};
  ok(appel.nom === "code-connexion" && /^Bearer /.test(appel.auth) && appel.corps === "{}",
    "le code part par la fonction Edge, avec le jeton du compte et un corps vide");
  ok(await page.isVisible("#code-saisie") && /Code envoyé au numéro qui finit par 96/.test(await etatCode(page)),
    "la saisie s'ouvre ; le message dit où le code est parti");
  const renvoi = await page.evaluate(() => {
    const b = document.querySelector("#code-renvoyer");
    return { off: b.disabled, texte: b.textContent };
  });
  ok(renvoi.off && /\(\d+ s\)/.test(renvoi.texte), "le renvoi patiente (« " + renvoi.texte + " »)");

  await page.fill("#code-chiffres", "12345");
  await page.click("#code-valider");
  await page.waitForTimeout(300);
  ok(note.codes.length === 0 && /six chiffres/.test(await etatCode(page)), "cinq chiffres ne partent pas");

  await page.fill("#code-chiffres", "111 111");
  await page.click("#code-valider");
  await page.waitForTimeout(600);
  ok((note.codes[0] || {}).code === "111111", "les espaces tapés ne gênent pas : « 111111 » part");
  ok(/Il vous reste 4 essais/.test(await etatCode(page)), "un code faux dit combien d'essais restent");

  await page.fill("#code-chiffres", "222222");
  await page.click("#code-valider");
  await page.waitForTimeout(2600);
  ok(/Connexion confirmée/.test(await toasts(page)) && await barre(page),
    "le bon code ouvre l'application");
  ok(lecturesCatalogue(note) > 0, "et c'est seulement alors qu'elle charge ce qu'elle montre");
  ok(note.journal.some((j) => /Connexion confirmée par SMS/.test(JSON.stringify(j))),
    "l'entrée se journalise : « Connexion confirmée par SMS »");
  sansErreur(erreurs);
  await ctx.close();
}

titre("1 bis. « Faire confiance à cet appareil pendant 1 mois »");
{
  const { page, ctx, erreurs, note } = await ouvrir({ moi: EQUIPE[0], etat: EXIGE,
    codes: [{ ok: true }] });
  ok(await page.isVisible("#cx-confiance") && !(await page.isChecked("#cx-confiance")) &&
     /Faire confiance à cet appareil pendant 1 mois/.test(await texteVue(page)),
    "la case est là, décochée");
  ok(note.reconnaitre.length === 0, "sans jeton gardé, on ne demande même pas à la base");
  await page.check("#cx-confiance");
  await page.click("#code-demander");
  await page.waitForTimeout(700);
  await page.fill("#code-chiffres", "222222");
  await page.click("#code-valider");
  await page.waitForTimeout(2600);
  const conf = note.confier[0] || {};
  const garde = await page.evaluate(() => localStorage.getItem("bizzoo-appareil-confiance") || "");
  ok(/^[0-9a-f]{64}$/.test(conf.jeton || "") && conf.jeton === garde,
    "code rendu, case cochée : confier_appareil part avec le jeton gardé sur l'appareil");
  ok(/plus de code sur cet appareil pendant 1 mois/.test(await toasts(page)) && await barre(page),
    "on le lui dit, et l'application s'ouvre");
  sansErreur(erreurs);
  await ctx.close();
}
{
  const { page, ctx, note } = await ouvrir({ moi: EQUIPE[0], etat: EXIGE, codes: [{ ok: true }] });
  await page.click("#code-demander");
  await page.waitForTimeout(700);
  await page.fill("#code-chiffres", "222222");
  await page.click("#code-valider");
  await page.waitForTimeout(2600);
  ok(note.confier.length === 0, "case décochée : l'appareil n'est pas gardé");
  await ctx.close();
}
{
  const jetonGarde = "ab".repeat(32);
  const { page, ctx, erreurs, note } = await ouvrir({ moi: EQUIPE[0], etat: EXIGE,
    appareil: jetonGarde, reconnu: true });
  ok((note.reconnaitre[0] || {}).jeton === jetonGarde, "l'appareil se présente avec son jeton");
  ok(!(await page.$("#code-demander")) && await barre(page) && note.edge.length === 0,
    "appareil de confiance : l'application s'ouvre, sans SMS");
  sansErreur(erreurs);
  await ctx.close();
}
{
  const { page, ctx } = await ouvrir({ moi: EQUIPE[0], etat: EXIGE, appareil: "cd".repeat(32), reconnu: false });
  ok(!!(await page.$("#code-demander")), "confiance expirée ou oubliée : le code est redemandé");
  await ctx.close();
}

titre("2. Les refus se lisent");
{
  const { page, ctx, erreurs } = await ouvrir({ moi: EQUIPE[1], etat: EXIGE,
    edge: [{ statut: 429, corps: { ok: false, raison: "trop_tot", attente: 20,
      message: "Un code vient de partir. Attendez 20 secondes avant d'en demander un autre." } }] });
  await page.click("#code-demander");
  await page.waitForTimeout(700);
  const renvoi = await page.evaluate(() => document.querySelector("#code-renvoyer").textContent);
  ok(/Attendez 20 secondes/.test(await etatCode(page)) && await page.isVisible("#code-saisie"),
    "« trop tôt » : le message de la fonction, et la saisie reste ouverte pour le code déjà parti");
  ok(/\((20|19) s\)/.test(renvoi), "le renvoi attend ce que la base a dit (« " + renvoi + " »)");
  sansErreur(erreurs);
  await ctx.close();
}
{
  const { page, ctx, erreurs, note } = await ouvrir({ moi: EQUIPE[2],
    etat: { ...EXIGE, numero: false, fin_numero: "" } });
  const t = await texteVue(page);
  ok(/n'a pas de\s+numéro/.test(t) && /superadministrateur/.test(t) && !(await page.$("#code-demander")),
    "un compte sans numéro est prévenu, sans bouton qui n'aboutirait pas");
  ok(!!(await page.$("#cx-sortir")) && note.edge.length === 0, "il peut se déconnecter ; aucun code n'est demandé");
  sansErreur(erreurs);
  await ctx.close();
}

titre("3. Rien n'est exigé, ou base d'avant : on entre comme avant");
for (const [cas, etat] of [["code non exigé", { ...EXIGE, sms_exige: false }], ["base d'avant le code", null]]) {
  const { page, ctx, erreurs, note } = await ouvrir({ moi: EQUIPE[1], etat });
  const t = await texteVue(page);
  ok(!/Confirmez votre connexion/.test(t) && await barre(page) && lecturesCatalogue(note) > 0,
    cas + " : l'application s'ouvre directement");
  sansErreur(erreurs);
  await ctx.close();
}

titre("4. Les Réglages : l'interrupteur des superadministrateurs");
{
  const etatSuper = { equipe: true, sms_exige: false, session_confirmee: false, numero: true,
    fin_numero: "96", tel_verifie: false };
  const { page, ctx, erreurs, note } = await ouvrir({ moi: EQUIPE[0], etat: etatSuper,
    codes: [{ ok: true }], hash: "#/reglages", attente: 3200 });
  const carte = () => page.evaluate(() => (document.querySelector("#section-sms-equipe") || {}).innerText || "");
  let t = await carte();
  ok(/Pas exigé pour l'instant/.test(t), "la carte dit que rien n'est exigé");
  /* (3.59.0) Le code ne vaut plus que pour les superadministrateurs : la
     carte ne compte qu'eux. Awa, modératrice sans numéro, entre quand même. */
  ok(/1 superadministrateur sur 1 a un numéro ; 0 l'a déjà confirmé/.test(t),
    "elle compte les superadministrateurs : 1 sur 1 a un numéro, 0 l'a confirmé");
  ok(!/Sans numéro/.test(t) && !/Awa/.test(t),
    "la modératrice sans numéro n'est pas citée : elle n'a pas de code à rendre");
  ok(/Les autres comptes/.test(t) && /mot de passe seul/.test(t),
    "la carte dit que les autres comptes entrent avec leur mot de passe seul");
  ok(await page.isDisabled("#sms-equipe-exige"), "l'interrupteur reste fermé tant que le superadmin n'a pas son code");
  ok(/finit par 96/.test(t) && !!(await page.$("#sms-equipe-bloc #code-demander")),
    "il est invité à recevoir d'abord son propre code");

  await page.click("#sms-equipe-bloc #code-demander");
  await page.waitForTimeout(700);
  await page.fill("#sms-equipe-bloc #code-chiffres", "333333");
  await page.click("#sms-equipe-bloc #code-valider");
  await page.waitForTimeout(1500);
  t = await carte();
  ok(/la passerelle livre/.test(await toasts(page)) && /Votre connexion est confirmée par SMS/.test(t),
    "son code rendu, la carte le constate");
  ok(!(await page.isDisabled("#sms-equipe-exige")), "et l'interrupteur s'ouvre");

  /* « Annuler » n'envoie rien. */
  await page.check("#sms-equipe-exige", { force: true });
  await page.click("#sms-equipe-enregistrer");
  await page.waitForTimeout(500);
  ok(/Exiger un code SMS des superadministrateurs/.test(await page.evaluate(() => document.body.innerText)),
    "allumer demande confirmation");
  await page.click("[data-role=annuler]");
  await page.waitForTimeout(500);
  ok(note.regler.length === 0 && !(await page.isChecked("#sms-equipe-exige")),
    "« Annuler » : rien ne part, et l'interrupteur revient");

  await page.check("#sms-equipe-exige", { force: true });
  await page.click("#sms-equipe-enregistrer");
  await page.waitForTimeout(500);
  await page.click("[data-role=ok]");
  await page.waitForTimeout(1500);
  ok((note.regler[0] || {}).exige === true, "confirmé : la base reçoit « exige: true »");
  ok(/exigé des superadministrateurs/.test(await toasts(page)) && /Exigé des superadministrateurs/.test(await carte()),
    "et la carte le dit");
  sansErreur(erreurs);
  await ctx.close();
}

titre("5. Les comptes disent qui les a créés");
{
  const { page, ctx, erreurs, note } = await ouvrir({ moi: EQUIPE[0],
    etat: { equipe: true, sms_exige: false, session_confirmee: false, numero: true, fin_numero: "96" },
    hash: "#/comptes", attente: 3200 });
  const traces = await page.evaluate(() => [...document.querySelectorAll(".compte-trace")].map((e) => e.innerText));
  const ligne = (motif) => traces.find((x) => motif.test(x)) || "";
  ok(/Créé le 10 octobre 2026 à 14:05 par Sena \(superadministrateur\)/.test(ligne(/Sena/)),
    "le créateur et l'heure de Cotonou (« " + ligne(/Sena/) + " »)");
  ok(/numéro vérifié/.test(ligne(/Sena/)), "un numéro confirmé par un code se voit");
  ok(/par Rohim \(administrateur\)/.test(ligne(/Rohim \(administrateur\)/)) &&
     /sans numéro/.test(ligne(/Rohim \(administrateur\)/)),
    "un compte sans numéro se voit aussi");
  ok(/hors de l'application/.test(ligne(/hors de/)) && /jamais confirmé/.test(ligne(/hors de/)),
    "un compte né hors de l'application le dit, au lieu d'un blanc");

  await page.click("[data-compte='" + CHEF + "']");
  await page.waitForTimeout(600);
  const feuille = await page.evaluate(() => document.body.innerText);
  ok(/Créé le 10 octobre 2026 à 14:05 par Sena/.test(feuille) &&
     /C'est là que part son code de connexion par SMS/.test(feuille),
    "la fiche reprend la trace, et dit à quoi sert le numéro");
  await page.keyboard.press("Escape");
  await page.waitForTimeout(400);

  await page.evaluate(() => { location.hash = "#/comptes"; });
  await page.waitForTimeout(1200);
  await page.click("#cp-nouveau");
  await page.waitForTimeout(500);
  await page.fill("#nc-email", "nouveau@bizzoo.bj");
  await page.fill("#nc-mdp", "essai-123456");
  await page.click("#nc-creer");
  await page.waitForTimeout(700);
  const refus = await page.evaluate(() => (document.querySelector("#nc-resultat") || {}).innerText || "");
  ok(/numéro de téléphone/.test(refus) && note.signup.length === 0,
    "sans numéro, le compte ne se crée pas — et rien ne part chez Supabase");
  sansErreur(erreurs);
  await ctx.close();
}

titre("6. Les clients disent par quelle porte ils sont entrés");
{
  const client = (id, email) => ({ id, nom: "Client " + id.slice(0, 2), email, tel: "0197000011",
    indicatif: "229", tel_verifie: !email, adresse: "", cree_le: "2026-10-12T09:15:00Z",
    type_compte: "client", revendeur_etat: "aucune", commandes: 0, payees: 0, total_paye: 0 });
  for (const [cas, c, attendu] of [
    ["par son numéro", client("c1000000-0000-4000-8000-000000000001", null), /avec son numéro, confirmé par un code SMS/],
    ["par son e-mail", client("c2000000-0000-4000-8000-000000000002", "awa@essai.bj"), /avec son adresse e-mail/]]) {
    const { page, ctx, erreurs } = await ouvrir({ moi: EQUIPE[0],
      etat: { equipe: true, sms_exige: false, session_confirmee: false, numero: true, fin_numero: "96" },
      clients: [c], hash: "#/client/" + c.id, attente: 3200 });
    const t = await texteVue(page);
    ok(/Compte ouvert le 12 octobre 2026 à 10:15, par le client lui-même/.test(t) && attendu.test(t),
      "ouvert " + cas + " : la fiche le dit");
    sansErreur(erreurs);
    await ctx.close();
  }
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec." : "\nTous les constats sont bons.");
process.exit(echecs ? 1 : 0);
