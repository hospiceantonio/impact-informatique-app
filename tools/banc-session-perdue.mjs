/* =========================================================
   La session qui tombait en silence (3.63.0)
   =========================================================
   CE QUE LE BANC GARDE. Le 21 octobre 2026, des commandes de test sont
   nées sans compte rattaché alors que leurs auteurs se croyaient
   connectés : la session du téléphone était tombée — fermée depuis un
   autre appareil — et l'application l'effaçait sans un mot ; l'écran de
   commande, prérempli, laissait partir la commande en visiteur.

     1. UN SEUL RAFRAÎCHISSEMENT À LA FOIS : les écrans qui s'ouvrent
        ensemble au démarrage ne tournent qu'une fois la clé, et la
        session renouvelée est rangée ;
     2. REFUSÉE MAIS RENOUVELÉE AILLEURS : un autre onglet a rangé une
        session plus neuve pendant l'appel — on l'adopte, sans message ;
     3. PERDUE POUR DE BON, ELLE SE DIT : le client en est averti, un
        drapeau reste sur le téléphone, et l'écran de commande propose
        de se reconnecter — ou de commander sans compte, en le sachant —
        au lieu du formulaire ; aucune commande ne part d'elle-même ;
     4. CONNECTÉ EN OUVRANT L'ÉCRAN, PLUS AU MOMENT DE PAYER : la
        commande ne part pas en visiteur, l'écran se redessine et le dit ;
     5. « SE DÉCONNECTER » NE FERME QUE CE TÉLÉPHONE (scope=local) ;
     6. SANS COMPTE, LE NUMÉRO SUIT AUSSI : le reçu montre les étapes de
        chaque boutique, mais pas le bouton « J'ai bien reçu » — la base
        n'accepte cette parole que d'un compte, et le reçu dit comment
        la donner ;
     7. DES COMMANDES PASSÉES D'ICI SANS COMPTE, UN NUMÉRO VÉRIFIÉ : elles
        se rattachent d'elles-mêmes en ouvrant « Mes commandes », une
        fois par ouverture.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-session-perdue.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-session-perdue.mjs");
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
const FICHE = { id: MOI, nom: "Awa", tel: "0197000011", indicatif: "229", tel_verifie: true,
  type_compte: "client", revendeur_etat: "aucune", adresse: "Cotonou, Fidjrossè" };

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64")
  .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const jwt = (claims) => b64({ alg: "HS256", typ: "JWT" }) + "." + b64(claims) + ".signature";
const sessionDe = (refresh, dansMs) => ({
  access_token: jwt({ sub: MOI, phone: "2290197000011", email: "", session_id: "a1000000-0000-4000-8000-000000000001" }),
  refresh_token: refresh, expire_a: Date.now() + dansMs, email: "", tel: "2290197000011",
});

/** Une commande payée, telle que ce téléphone la garde après l'avoir passée. */
const copieLocale = (id, numero) => ({
  id, numero, total: 7500, devise: "FCFA", etat: "payee", acompte: 7500, taux_acompte: 100, reste: 0,
  frais_livraison: 0, client: { nom: "Awa", tel: "0197000011", indicatif: "229", adresse: "Cotonou" },
  boutiques: [{ id: "bou_a", nom: "Impact Informatique", montant: 7500,
    lignes: [{ nom: "Souris sans fil", code: "100061", reference: "SOU-1", prix: 7500, quantite: 1 }] }],
  gardeeLe: Date.now() - 3600000,
});
/** La même, telle que la base la rend à un compte. */
const enBase = (id, numero) => ({
  id, numero, total: 7500, devise: "FCFA", etat: "payee", remarque: "", note: "", cree_le: "2026-10-21T10:00:00Z",
  revendeur: false, client_nom: "Awa", client_tel: "0197000011", client_indicatif: "229", client_adresse: "Cotonou",
  acompte: 7500, taux_acompte: 100, verse: 7500, restes: { reste: 0, boutiques: {} }, frais_livraison: 0,
  commande_lignes: [{ boutique_id: "bou_a", produit_id: "prod_1", nom: "Souris sans fil", code: "100061",
    reference: "SOU-1", prix: 7500, quantite: 1, etat: "remise", confirme_le: null }],
});

/**
 * Une ouverture de l'application, avec un faux Supabase qui note tout.
 *   session     : { refresh, dansMs } — la session gardée sur le téléphone
 *   token       : "ok" | "introuvable" | "introuvable-mais-rangee"
 *   panier      : un article dans le panier
 *   commandes   : les copies locales (« bizzoo-commandes »)
 *   suivi       : ce que rend « suivre_commande »
 *   rattachee   : la commande que la base rend APRÈS « rattacher_mes_commandes »
 */
async function ouvrir(o = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1600 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(({ session, panier, commandes }) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
    localStorage.removeItem("bizzoo-session-perdue");
    if (session) localStorage.setItem("bizzoo-session", JSON.stringify(session));
    if (panier) localStorage.setItem("bizzoo-panier", JSON.stringify([{ produitId: "prod_1", quantite: 1 }]));
    if (commandes) localStorage.setItem("bizzoo-commandes", JSON.stringify(commandes));
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
  }, {
    session: o.session ? sessionDe(o.session.refresh || "r", o.session.dansMs) : null,
    panier: !!o.panier,
    commandes: o.commandes || null,
  });

  const note = { token: [], logout: [], creer: 0, suivre: 0, rattacher: 0 };
  let rattachee = false;

  await page.route("**/auth/v1/**", async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const chemin = url.pathname.replace(/^.*\/auth\/v1\//, "");
    const json = (status, corps) => route.fulfill({ status, contentType: "application/json", body: JSON.stringify(corps) });
    const corps = (() => { try { return JSON.parse(req.postData() || "{}"); } catch (_) { return {}; } })();
    if (chemin === "settings") return json(200, { external: { email: true, phone: true }, disable_signup: false });
    if (chemin === "token" && url.searchParams.get("grant_type") === "refresh_token") {
      note.token.push(corps.refresh_token || "");
      if (o.token === "introuvable-mais-rangee") {
        /* Un autre onglet range une session plus neuve pendant l'appel. */
        await page.evaluate((s) => localStorage.setItem("bizzoo-session", JSON.stringify(s)),
          sessionDe("r-autre", 3600000));
      }
      if (o.token === "introuvable" || o.token === "introuvable-mais-rangee") {
        return json(400, { code: 400, error_code: "refresh_token_not_found",
          msg: "Invalid Refresh Token: Refresh Token Not Found" });
      }
      return json(200, { access_token: sessionDe("", 0).access_token, token_type: "bearer",
        expires_in: 3600, refresh_token: "r2", user: { id: MOI, phone: "2290197000011", email: "" } });
    }
    if (chemin === "logout") {
      note.logout.push({ portee: url.searchParams.get("scope") || "", auth: req.headers()["authorization"] || "" });
      return route.fulfill({ status: 204, body: "" });
    }
    return json(200, {});
  });

  await page.route("**/rest/v1/**", async (r) => {
    const req = r.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/creer_commande") { note.creer++; return r.fulfill({ status: 500, body: "{}" }); }
    if (c === "rpc/suivre_commande") { note.suivre++; return d(o.suivi || null); }
    if (c === "rpc/rattacher_mes_commandes") { note.rattacher++; rattachee = true; return d(o.rattachee ? 1 : 0); }
    if (c === "rpc/mon_compte_livreur") return d({ livreur: false, double: false });
    if (c.startsWith("rpc/")) return d([]);
    if (c.startsWith("clients")) return d([FICHE]);
    if (c.startsWith("profils")) return d([]);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    if (c.startsWith("commandes")) return d(rattachee && o.rattachee ? [o.rattachee] : []);
    if (c.startsWith("produits")) return d([PRODUIT]);
    if (c.startsWith("categories")) return d([]);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: true, fournisseur: "kkiapay",
      cle_publique: "pk_essai", bac_a_sable: true, taux_acompte: 100, frais_livraison: 0 }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1700);
  return { page, ctx, erreurs, note };
}

const aller = async (page, hash, attente = 1400) => {
  await page.evaluate((h) => { location.hash = h; }, hash);
  await page.waitForTimeout(attente);
};
const toasts = (page) => page.evaluate(() => (window.__toasts || []).join(" | "));
const garde = (page) => page.evaluate(() => JSON.parse(localStorage.getItem("bizzoo-session") || "null"));
const drapeau = (page) => page.evaluate(() => localStorage.getItem("bizzoo-session-perdue"));
const connecte = (page) => page.evaluate(() => Compte.connecte());
const texte = (page) => page.evaluate(() => document.querySelector("#vue").textContent || "");
const existe = (page, s) => page.evaluate((s) => !!document.querySelector(s), s);
const compte = (page, s) => page.evaluate((s) => document.querySelectorAll(s).length, s);
const sansErreur = (erreurs) => ok(!erreurs.length, "aucune erreur dans la page" +
  (erreurs.length ? " : " + erreurs[0] : ""));

titre("1. Un seul rafraîchissement à la fois");
{
  const { page, ctx, erreurs, note } = await ouvrir({ session: { refresh: "r", dansMs: -1000 }, token: "ok" });
  await aller(page, "#/mes-commandes");
  await aller(page, "#/compte");
  ok(note.token.length === 1, "une seule demande de rafraîchissement pour tous les écrans (" + note.token.length + ")");
  ok(note.token[0] === "r", "avec le jeton que le téléphone gardait");
  const s = await garde(page);
  ok(!!s && s.refresh_token === "r2", "la session renouvelée est rangée sur le téléphone");
  ok(await connecte(page), "et le client est toujours connecté");
  ok(!(await drapeau(page)), "aucune perte n'est notée");
  sansErreur(erreurs);
  await ctx.close();
}

titre("2. Refusée, mais renouvelée par un autre onglet pendant l'appel");
{
  const { page, ctx, erreurs, note } = await ouvrir({ session: { refresh: "r", dansMs: -1000 },
    token: "introuvable-mais-rangee" });
  await aller(page, "#/mes-commandes");
  ok(note.token.length === 1, "une demande, refusée");
  const s = await garde(page);
  ok(!!s && s.refresh_token === "r-autre", "la session rangée par l'autre onglet est adoptée");
  ok(await connecte(page), "le client reste connecté");
  ok(!/session a expiré/.test(await toasts(page)), "sans message : rien n'a été perdu");
  ok(!(await drapeau(page)), "et aucune perte n'est notée");
  sansErreur(erreurs);
  await ctx.close();
}

titre("3. Perdue pour de bon : dite, notée, et l'écran de commande la rappelle");
{
  const { page, ctx, erreurs, note } = await ouvrir({ session: { refresh: "r", dansMs: -1000 },
    token: "introuvable", panier: true });
  ok(note.token.length === 1, "une demande, refusée");
  ok(!(await connecte(page)), "le client n'est plus connecté");
  ok(!(await garde(page)), "la session est retirée du téléphone");
  ok(/Votre session a expiré/.test(await toasts(page)), "et on le lui dit : « Votre session a expiré »");
  ok(!!(await drapeau(page)), "la perte est notée sur le téléphone");

  await aller(page, "#/commande");
  ok(/Votre session a expiré/.test(await texte(page)), "l'écran de commande rappelle la perte");
  ok(await existe(page, 'a[href="#/connexion"]'), "« Se reconnecter » est proposé");
  ok(await existe(page, "#co-sans-compte"), "et « Commander sans compte », en le sachant");
  ok(!(await existe(page, "#co-nom")), "pas de formulaire prérempli");
  ok(note.creer === 0, "aucune commande n'est partie");

  /* La perte survit à une fermeture de l'application. */
  await page.reload({ waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1700);
  await aller(page, "#/commande");
  ok(/Votre session a expiré/.test(await texte(page)), "rouverte, l'application le rappelle encore");

  await page.click("#co-sans-compte");
  await page.waitForTimeout(900);
  ok(await existe(page, "#co-nom"), "« Commander sans compte » ouvre le formulaire");
  ok(await existe(page, "#co-connexion"), "avec le rappel « Vous avez un compte BIZZOO ? »");
  ok(!(await drapeau(page)), "et la perte n'est plus notée : le client a choisi");
  ok(note.creer === 0, "toujours aucune commande partie d'elle-même");
  sansErreur(erreurs);
  await ctx.close();
}

titre("4. Connecté en ouvrant l'écran, plus au moment de payer");
{
  const { page, ctx, erreurs, note } = await ouvrir({ session: { refresh: "r", dansMs: 61000 },
    token: "introuvable", panier: true });
  ok(await connecte(page), "connecté à l'ouverture, sans rafraîchir (" + note.token.length + " demande)");
  await aller(page, "#/commande");
  ok(await existe(page, "#co-payer") && !(await existe(page, "#co-connexion")),
    "l'écran de commande s'ouvre en client connecté");
  /* Le temps passe : la session arrive à moins d'une minute de sa fin. */
  await page.waitForFunction(() => {
    const s = JSON.parse(localStorage.getItem("bizzoo-session") || "null");
    return !s || s.expire_a - Date.now() < 59000;
  }, null, { timeout: 10000 });
  await page.click("#co-payer");
  await page.waitForTimeout(1200);
  ok(note.token.length === 1, "le paiement a demandé le rafraîchissement, refusé");
  ok(note.creer === 0, "la commande n'est PAS partie en visiteur");
  ok(/Votre session a expiré/.test(await toasts(page)), "le client est averti");
  ok(/Votre session a expiré/.test(await texte(page)) && (await existe(page, "#co-sans-compte")),
    "et l'écran se redessine sur le choix : se reconnecter, ou sans compte");
  sansErreur(erreurs);
  await ctx.close();
}

titre("5. « Se déconnecter » ne ferme que ce téléphone");
{
  const { page, ctx, erreurs, note } = await ouvrir({ session: { refresh: "r", dansMs: 3600000 }, token: "ok" });
  await page.evaluate(() => Compte.deconnecter());
  await page.waitForTimeout(500);
  ok(note.logout.length === 1, "la déconnexion est demandée à la base");
  ok(note.logout[0] && note.logout[0].portee === "local", "pour CE téléphone seulement (scope=local)");
  ok(!(await connecte(page)) && !(await drapeau(page)), "déconnecté, sans que ce soit une perte");
  sansErreur(erreurs);
  await ctx.close();
}

titre("6. Sans compte, le numéro suit aussi — mais ne signe pas");
{
  const suivi = { numero: "BZ-0F1", etat: "payee", total: 7500, devise: "FCFA", taux_acompte: 100,
    acompte: 7500, verse: 7500, reste: 0, restes: {}, encaissements: {}, paye_livraison: 0,
    etats: { bou_a: { etat: "remise", confirme: false } } };
  const { page, ctx, erreurs, note } = await ouvrir({ commandes: [copieLocale("cmd_f1", "BZ-0F1")], suivi });
  await aller(page, "#/commande/cmd_f1", 2200);
  ok(note.suivre >= 1, "le reçu demande le suivi par numéro");
  ok(await existe(page, ".re-suivi"), "les étapes s'affichent");
  ok((await compte(page, ".re-etape.faite")) === 5, "jusqu'à « Remise » (5 étapes faites)");
  ok(!(await existe(page, ".re-confirmer")), "pas de bouton « J'ai bien reçu » sans compte");
  ok(/passée sans compte/.test(await texte(page)), "le reçu dit comment confirmer : entrer avec ce numéro");
  const copie = await page.evaluate(() => JSON.parse(localStorage.getItem("bizzoo-commandes") || "[]")[0]);
  ok(copie && copie.boutiques[0].etat === "remise", "l'étape est gardée sur le téléphone");
  await aller(page, "#/mes-commandes");
  ok(await existe(page, ".re-barre"), "la liste montre la barre de suivi");
  ok(!(await existe(page, "[data-recu]")), "sans bouton « J'ai bien reçu »");
  sansErreur(erreurs);
  await ctx.close();
}

titre("7. Des commandes passées d'ici sans compte, un numéro vérifié : rattachées d'elles-mêmes");
{
  const { page, ctx, erreurs, note } = await ouvrir({ session: { refresh: "r", dansMs: 3600000 }, token: "ok",
    commandes: [copieLocale("cmd_g1", "BZ-0G1")], rattachee: enBase("cmd_g1", "BZ-0G1") });
  await aller(page, "#/mes-commandes", 2600);
  ok(note.rattacher === 1, "« rattacher_mes_commandes » est demandé une fois");
  ok(/1 commande rattachée/.test(await toasts(page)), "et le client en est informé");
  ok(await existe(page, "[data-recu]"), "la commande, désormais à son compte, offre « J'ai bien reçu »");
  ok(!/Ce téléphone/.test(await texte(page)), "elle n'est plus « Ce téléphone » seulement");
  await aller(page, "#/");
  await aller(page, "#/mes-commandes", 1800);
  ok(note.rattacher === 1, "une fois par ouverture, pas à chaque visite");
  sansErreur(erreurs);
  await ctx.close();
}

await nav.close();
console.log("\n" + (echecs ? echecs + " ÉCHEC(S)" : "Tout tient."));
process.exit(echecs ? 1 : 0);
