/* =========================================================
   Entrer chez BIZZOO avec son numéro (3.58.0)
   =========================================================
   CE QUE LE BANC GARDE. Le SMS ouvert, un compte se crée et s'ouvre
   avec un numéro et un code ; l'e-mail ne sert plus qu'aux comptes
   d'avant, une seule fois, le temps de confirmer leur numéro.

     1. « SE CONNECTER » OUVRE SUR LE NUMÉRO, et l'e-mail recule derrière
        un lien. Le code part au format que GoTrue exige (+229…), avec
        « compte: client » — sans lui, la base ferait de l'acheteur une
        fiche d'équipe en attente ;
     2. LE SIXIÈME CHIFFRE VALIDE, UNE FOIS : une touche « Entrée » juste
        derrière ne renvoie pas le même code, déjà consommé ;
     3. UN COMPTE NÉ À LA PORTE « SE CONNECTER » donne son nom — et ce
        nom s'écrit SEUL, sans effacer une adresse ;
     4. « CRÉER MON COMPTE » : le nom, le numéro, le code. Plus d'e-mail
        ni de mot de passe. La demande de revendeur part une fois le
        compte ouvert ; avec un numéro qui avait déjà son compte, on le
        dit, et l'on ne refait pas une demande déjà acquise ;
     5. L'ANCIEN COMPTE E-MAIL n'entre pas sur son seul mot de passe :
        il confirme son numéro d'abord, avec la session QUI ATTEND — rien
        n'est gardé sur le téléphone avant le code. « Annuler » le laisse
        dehors. Déjà confirmé, ou de l'équipe : il entre ;
     6. RESTÉ CONNECTÉ DEPUIS AVANT, il est prié de confirmer dans « Mon
        compte », et avant de commander — puis la commande reprend ;
     7. LE SMS FERMÉ OU INCERTAIN : on n'enferme personne. Fermé,
        l'e-mail revient devant ; incertain, le numéro reste montré mais
        le mot de passe suffit encore.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-connexion-sms.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-connexion-sms.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const MOI = "44444444-4444-4444-4444-444444444444";
const ANCIEN = "55555555-5555-4555-8555-555555555555";
const BOU = [{ id: "bou_a", nom: "Impact Informatique", secteur: "Informatique", categorie_id: "cat_hightech",
  icone: "portable", couleur: "#0047D9", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }];
const PRODUIT = { id: "prod_1", code: "100061", nom: "Souris sans fil", reference: "SOU-1", prix: 7500,
  boutique_id: "bou_a", categorie_id: "cat_hightech", sous_categorie_id: null, stock: 5,
  disponible: true, sur_commande: false, images: [], video: "", en_avant: false,
  cree_le: "2026-09-01T10:00:00Z", modifie_le: "2026-09-01T10:00:00Z" };

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64")
  .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const jwt = (claims) => b64({ alg: "HS256", typ: "JWT" }) + "." + b64(claims) + ".signature";

/**
 * Une ouverture de l'application, avec un faux Supabase qui note tout.
 *   sms      : true / false / "panne"
 *   session  : une session déjà gardée sur le téléphone — { phone } pour
 *              un compte au numéro confirmé, {} pour un compte e-mail d'avant
 *   fiche    : la ligne « clients » que la base rend
 *   verifie  : ce que rend la vérification du code — { nouveau }
 *   motDePasse : ce que rend la connexion par e-mail — { phone, equipe }
 */
async function ouvrir(o = {}) {
  const sms = o.sms === undefined ? true : o.sms;
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1400 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(({ session, panier }) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
    if (session) localStorage.setItem("bizzoo-session", JSON.stringify(session));
    if (panier) localStorage.setItem("bizzoo-panier", JSON.stringify([{ produitId: "prod_1", quantite: 1 }]));
    /* Chaque message affiché, gardé : ils s'effacent au bout de trois
       secondes, et un constat ne doit pas dépendre du moment exact. */
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
    session: o.session ? {
      access_token: jwt({ sub: o.session.sub || ANCIEN, email: o.session.email || "awa@essai.bj",
        phone: o.session.phone || "", session_id: "a1000000-0000-4000-8000-000000000001" }),
      refresh_token: "r", expire_a: Date.now() + 3600000,
      email: o.session.email || "awa@essai.bj", tel: o.session.phone || "",
    } : null,
    panier: !!o.panier,
  });

  const note = { otp: [], verify: [], put: [], token: [], patch: [], profils: [], clients: [], rattacher: 0 };
  let fiche = o.fiche === undefined
    ? { id: MOI, nom: "Awa", tel: "0197000011", indicatif: "229", tel_verifie: false,
        type_compte: "client", revendeur_etat: "aucune", adresse: "Cotonou, Fidjrossè" }
    : o.fiche;
  const maintenant = new Date();
  const ilYa = (min) => new Date(maintenant.getTime() - min * 60000).toISOString();

  await page.route("**/auth/v1/**", async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const chemin = url.pathname.replace(/^.*\/auth\/v1\//, "");
    const json = (status, corps) => route.fulfill({ status, contentType: "application/json", body: JSON.stringify(corps) });
    const corps = (() => { try { return JSON.parse(req.postData() || "{}"); } catch (_) { return {}; } })();
    if (chemin === "settings") {
      if (sms === "panne") return route.fulfill({ status: 500, body: "{}" });
      return json(200, { external: { email: true, phone: sms === true }, disable_signup: false });
    }
    if (chemin === "otp") { note.otp.push(corps); return json(200, {}); }
    if (chemin === "user" && req.method() === "PUT") {
      note.put.push({ corps, auth: req.headers()["authorization"] || "" });
      return json(200, { id: ANCIEN, email: "awa@essai.bj", phone: "", new_phone: corps.phone });
    }
    if (chemin === "verify") {
      note.verify.push(corps);
      const national = String(corps.phone || "").replace(/\D/g, "");
      /* Ce que fait le vrai déclencheur « au_numero_confirme » : la fiche
         apprend le numéro confirmé, et son drapeau. */
      if (fiche) fiche = { ...fiche, tel: national.replace(/^229/, ""), tel_verifie: true };
      const qui = corps.type === "phone_change" ? ANCIEN : MOI;
      const nouveau = !!(o.verifie && o.verifie.nouveau);
      return json(200, {
        access_token: jwt({ sub: qui, phone: national, email: corps.type === "phone_change" ? "awa@essai.bj" : "",
          session_id: "b2000000-0000-4000-8000-000000000002" }),
        token_type: "bearer", expires_in: 3600, refresh_token: "rv",
        user: { id: qui, phone: national, email: corps.type === "phone_change" ? "awa@essai.bj" : "",
          phone_confirmed_at: maintenant.toISOString(),
          created_at: nouveau ? ilYa(2) : "2026-01-05T09:00:00Z",
          last_sign_in_at: maintenant.toISOString() },
      });
    }
    if (chemin.startsWith("token")) {
      note.token.push(corps);
      const m = o.motDePasse || {};
      return json(200, {
        access_token: jwt({ sub: ANCIEN, email: corps.email, phone: m.phone || "",
          session_id: "c3000000-0000-4000-8000-000000000003" }),
        token_type: "bearer", expires_in: 3600, refresh_token: "rp",
        user: { id: ANCIEN, email: corps.email, phone: m.phone || "",
          ...(m.phone ? { phone_confirmed_at: "2026-02-01T10:00:00Z" } : {}),
          created_at: "2026-01-05T09:00:00Z", last_sign_in_at: maintenant.toISOString() },
      });
    }
    if (chemin === "logout") return route.fulfill({ status: 204, body: "" });
    return json(200, {});
  });

  await page.route("**/rest/v1/**", async (r) => {
    const req = r.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "") + new URL(req.url()).search;
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    const auth = req.headers()["authorization"] || "";
    if (c.startsWith("profils")) {
      note.profils.push(auth);
      return d(o.motDePasse && o.motDePasse.equipe ? [{ id: ANCIEN }] : []);
    }
    if (c.startsWith("clients")) {
      if (req.method() === "PATCH") {
        const corps = JSON.parse(req.postData() || "{}");
        note.patch.push(corps);
        fiche = { ...(fiche || {}), ...corps };
        if (corps.type_compte === "revendeur" && fiche.revendeur_etat !== "validee") fiche.revendeur_etat = "en_attente";
        return d([fiche]);
      }
      note.clients.push(auth);
      return d(fiche ? [fiche] : []);
    }
    if (c.startsWith("rpc/rattacher_mes_commandes")) { note.rattacher++; return d(2); }
    if (c.startsWith("rpc/mes_prix")) return d([]);
    if (c.startsWith("rpc/produits_populaires")) return d([]);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: !!o.compteObligatoire }]);
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
  return { page, ctx, erreurs, note };
}

const aller = async (page, hash, attente = 1300) => {
  await page.evaluate((h) => { location.hash = h; }, hash);
  await page.waitForTimeout(attente);
};
const toasts = (page) => page.evaluate(() => (window.__toasts || []).join(" | "));
const hash = (page) => page.evaluate(() => location.hash);
const visible = (page, s) => page.evaluate((s) => {
  const el = document.querySelector(s);
  return !!el && !el.closest("[hidden]");
}, s);
const garde = (page) => page.evaluate(() => JSON.parse(localStorage.getItem("bizzoo-session") || "null"));
const connecte = (page) => page.evaluate(() => Compte.connecte());
const sansErreur = (erreurs) => ok(!erreurs.length, "aucune erreur dans la page" +
  (erreurs.length ? " : " + erreurs[0] : ""));
/* Taper un code comme au téléphone : chiffre après chiffre. */
const taperCode = async (page, code) => {
  await page.click("#cp-code");
  await page.keyboard.type(code, { delay: 20 });
};

titre("1. « Se connecter » ouvre sur le numéro");
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true, fiche: { id: MOI, nom: "Awa",
    tel: "0197121596", indicatif: "229", tel_verifie: true, type_compte: "client",
    revendeur_etat: "aucune", adresse: "Cotonou" } });
  await aller(page, "#/connexion");
  ok(await visible(page, "#cp-tel") && await visible(page, "#cp-envoyer"), "le numéro est devant");
  ok(!(await page.$("#cp-email")) && !(await page.$("#cp-mdp")), "ni e-mail, ni mot de passe à l'écran");
  ok(!!(await page.$('a[href="#/connexion-email"]')), "les comptes d'avant ont leur lien");
  ok(!!(await page.$('a[href="#/inscription"]')), "« Créer mon compte » reste");

  await page.click("#cp-envoyer");
  await page.waitForTimeout(400);
  ok(note.otp.length === 0 && /Tapez votre numéro/.test(await toasts(page)),
    "sans numéro, aucun code ne part");

  await page.fill("#cp-tel", "01 97 12 15 96");
  await page.click("#cp-envoyer");
  await page.waitForTimeout(700);
  const envoi = note.otp[0] || {};
  ok(envoi.phone === "+2290197121596", "le code part au format de GoTrue (" + envoi.phone + ")");
  ok(envoi.create_user === true && envoi.data && envoi.data.compte === "client",
    "avec « compte: client » : la base n'en fera pas une fiche d'équipe");
  ok(await visible(page, "#cp-code") && /\+229 01 97 12 15 96/.test(await page.innerText("#vue")),
    "l'écran du code rappelle le numéro, par groupes de deux");

  titre("2. Le sixième chiffre valide, une fois");
  await taperCode(page, "123456");
  await page.keyboard.press("Enter");
  await page.waitForTimeout(1500);
  ok(note.verify.length === 1, "une seule vérification, malgré « Entrée » (" + note.verify.length + ")");
  const v = note.verify[0] || {};
  ok(v.type === "sms" && v.phone === "+2290197121596" && v.token === "123456",
    "le code vérifié est celui tapé, pour ce numéro");
  const s = await garde(page);
  ok(!!s && s.tel === "2290197121596", "la session est gardée, avec son numéro");
  ok(await hash(page) === "#/compte" && /Bonjour/.test(await toasts(page)),
    "le client entre : « Bonjour ! », et Mon compte");
  ok(!/Code incorrect/.test(await toasts(page)), "aucun « code incorrect » après coup");
  sansErreur(erreurs);
  await ctx.close();
}

titre("3. Un compte né à la porte « Se connecter » donne son nom");
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true, verifie: { nouveau: true },
    fiche: { id: MOI, nom: "", tel: "0197121596", indicatif: "229", tel_verifie: true,
      type_compte: "client", revendeur_etat: "aucune", adresse: "Cotonou, Akpakpa" } });
  await aller(page, "#/connexion");
  await page.fill("#cp-tel", "0197121596");
  await page.click("#cp-envoyer");
  await page.waitForTimeout(600);
  await taperCode(page, "111111");
  await page.waitForTimeout(1500);
  ok(await visible(page, "#cp-nommer"), "on lui demande son nom");
  await page.click("#cp-nommer-ok");
  await page.waitForTimeout(300);
  ok(note.patch.length === 0 && /Votre nom/.test(await toasts(page)), "un nom vide ne part pas");
  await page.fill("#cp-nom", "Awa Dossou");
  await page.click("#cp-nommer-ok");
  await page.waitForTimeout(1200);
  const p = note.patch[0] || {};
  ok(p.nom === "Awa Dossou" && Object.keys(p).sort().join(",") === "maj_le,nom",
    "seul le nom s'écrit — l'adresse déjà donnée ne s'efface pas (" + Object.keys(p).join(",") + ")");
  ok(await hash(page) === "#/compte" && /Bienvenue/.test(await toasts(page)), "« Bienvenue ! », et Mon compte");
  sansErreur(erreurs);
  await ctx.close();
}

titre("4. « Créer mon compte » : le nom, le numéro, le code");
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true, verifie: { nouveau: true },
    fiche: { id: MOI, nom: "Koffi Mensah", tel: "0161000022", indicatif: "229", tel_verifie: true,
      type_compte: "client", revendeur_etat: "aucune", adresse: "" } });
  await aller(page, "#/inscription");
  ok(!(await page.$("#cp-email")) && !(await page.$("#cp-mdp")), "plus d'e-mail ni de mot de passe");
  ok(await visible(page, "#cp-nom") && await visible(page, "#cp-tel") && await visible(page, "#cp-creer-tel"),
    "le nom, le numéro, et « Recevoir mon code »");

  await page.fill("#cp-tel", "0161000022");
  await page.click("#cp-creer-tel");
  await page.waitForTimeout(300);
  ok(note.otp.length === 0 && /Votre nom/.test(await toasts(page)), "sans nom, rien ne part");

  await page.fill("#cp-nom", "Koffi Mensah");
  await page.click('[data-type="revendeur"]');
  await page.click("#cp-creer-tel");
  await page.waitForTimeout(300);
  ok(note.otp.length === 0 && /quel commerce/.test(await toasts(page)),
    "« Pour revendre » demande d'abord quel commerce");

  await page.fill("#cp-message", "Boutique Mensah, accessoires téléphone");
  await page.fill("#cp-pos-adresse", "Dantokpa, face à la pharmacie");
  await page.click("#cp-creer-tel");
  await page.waitForTimeout(300);
  ok(note.otp.length === 0 && /Activez votre position/.test(await toasts(page)),
    "« Pour revendre » sans position du téléphone : rien ne part");
  /* La position du téléphone, simulée : sans elle, la demande de
     revendeur ne part plus (3.58.0). */
  await page.evaluate(() => {
    Object.defineProperty(navigator, "geolocation", { configurable: true, value: {
      getCurrentPosition: (ok) => ok({ coords: { latitude: 6.3561, longitude: 2.4334, accuracy: 15 } }) } });
  });
  await page.click("#cp-pos-relever");
  await page.waitForTimeout(300);
  await page.click("#cp-creer-tel");
  await page.waitForTimeout(700);
  const e = note.otp[0] || {};
  ok(e.phone === "+2290161000022" && e.data && e.data.nom === "Koffi Mensah" && e.data.compte === "client",
    "le code part avec le nom du nouveau compte");
  await taperCode(page, "222222");
  await page.waitForTimeout(1800);
  const demande = note.patch.find((x) => x.type_compte === "revendeur") || {};
  ok(demande.revendeur_message === "Boutique Mensah, accessoires téléphone" &&
     demande.revendeur_adresse === "Dantokpa, face à la pharmacie",
    "la demande de revendeur part une fois le compte ouvert, avec son commerce et son adresse");
  ok(/Votre demande est partie/.test(await toasts(page)) && await hash(page) === "#/compte",
    "« Bienvenue ! Votre demande est partie. »");
  sansErreur(erreurs);
  await ctx.close();
}

titre("4 bis. Un numéro qui avait déjà son compte");
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true, verifie: { nouveau: false },
    fiche: { id: MOI, nom: "Koffi Mensah", tel: "0161000022", indicatif: "229", tel_verifie: true,
      type_compte: "revendeur", revendeur_etat: "validee", adresse: "Cotonou" } });
  await aller(page, "#/inscription");
  await page.fill("#cp-nom", "K. Mensah");
  await page.click('[data-type="revendeur"]');
  await page.fill("#cp-message", "Ma boutique");
  await page.fill("#cp-tel", "0161000022");
  await page.click("#cp-creer-tel");
  await page.waitForTimeout(600);
  await taperCode(page, "333333");
  await page.waitForTimeout(1800);
  ok(/avait déjà son compte/.test(await toasts(page)), "on le dit : « Ce numéro avait déjà son compte »");
  ok(!note.patch.length, "ni le nom ni le statut de revendeur déjà acquis ne sont réécrits");
  sansErreur(erreurs);
  await ctx.close();
}

titre("5. L'ancien compte e-mail confirme son numéro avant d'entrer");
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true });
  await aller(page, "#/connexion");
  await page.click('a[href="#/connexion-email"]');
  await page.waitForTimeout(900);
  ok(await visible(page, "#cp-email") && /une dernière fois/.test(await page.innerText("#vue")),
    "la porte des comptes d'avant explique ce qui va suivre");
  await page.fill("#cp-email", "awa@essai.bj");
  await page.fill("#cp-mdp", "secret-essai");
  await page.click("#cp-entrer");
  await page.waitForTimeout(1300);
  ok(await visible(page, "#cp-confirmer-numero"), "le mot de passe est bon : on lui demande son numéro");
  ok(!(await garde(page)) && !(await connecte(page)),
    "il n'est PAS connecté : rien n'est gardé sur le téléphone avant le code");
  ok(await page.inputValue("#cp-tel") === "0197000011", "le numéro de sa fiche est déjà dans le champ");
  const jetonAttente = note.profils[0] || "";
  ok(!!jetonAttente && note.clients[0] === jetonAttente,
    "l'équipe et la fiche se lisent avec la session qui attend");

  await page.click("#cp-envoyer");
  await page.waitForTimeout(800);
  const put = note.put[0] || {};
  ok(put.corps.phone === "+2290197000011" && put.auth === jetonAttente,
    "le code part au nom de la session qui attend, vers ce numéro");
  await taperCode(page, "654321");
  await page.waitForTimeout(1800);
  const v = note.verify[0] || {};
  ok(v.type === "phone_change" && v.token === "654321", "le code se vérifie comme un changement de numéro");
  const s = await garde(page);
  ok(!!s && s.tel === "2290197000011" && await connecte(page), "il entre, avec son numéro confirmé");
  ok(note.rattacher === 1 && /Numéro confirmé\. 2 commandes retrouvées/.test(await toasts(page)),
    "ses commandes d'avant le rejoignent, et on le lui dit");
  ok(await hash(page) === "#/compte", "et il arrive dans Mon compte");
  await page.waitForTimeout(600);
  ok(!(await page.$("#cp-numero-requis")), "Mon compte ne lui redemande rien");
  sansErreur(erreurs);
  await ctx.close();
}

titre("5 bis. « Annuler » le laisse dehors");
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true });
  await aller(page, "#/connexion-email");
  await page.fill("#cp-email", "awa@essai.bj");
  await page.fill("#cp-mdp", "secret-essai");
  await page.click("#cp-entrer");
  await page.waitForTimeout(1300);
  await page.click("#cp-renoncer");
  await page.waitForTimeout(1000);
  ok(await hash(page) === "#/connexion" && await visible(page, "#cp-envoyer"),
    "retour à « Se connecter », sur le numéro");
  ok(!(await connecte(page)) && await page.evaluate(() => Compte.numeroEnAttente()) === null,
    "pas connecté, et la session qui attendait est oubliée");
  ok(note.put.length === 0, "aucun code n'est parti");
  sansErreur(erreurs);
  await ctx.close();
}

titre("5 ter. Déjà confirmé, ou de l'équipe : il entre");
for (const [cas, motDePasse] of [["numéro déjà confirmé", { phone: "2290197000011" }],
                                  ["compte de l'équipe", { equipe: true }]]) {
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true, motDePasse });
  await aller(page, "#/connexion-email");
  await page.fill("#cp-email", "awa@essai.bj");
  await page.fill("#cp-mdp", "secret-essai");
  await page.click("#cp-entrer");
  await page.waitForTimeout(1500);
  ok(!(await page.$("#cp-confirmer-numero")) && await connecte(page) && /Bonjour/.test(await toasts(page)),
    cas + " : il entre sans étape de plus");
  ok(note.put.length === 0, cas + " : aucun code ne part");
  sansErreur(erreurs);
  await ctx.close();
}

titre("6. Resté connecté depuis avant : Mon compte, puis la commande");
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true, session: {} });
  await aller(page, "#/compte", 1800);
  ok(await visible(page, "#cp-numero-requis") && !(await page.$("#cp-verifier")),
    "Mon compte demande de confirmer le numéro — une carte, devant le reste");
  await page.click("#cp-confirmer");
  await page.waitForTimeout(500);
  ok(await visible(page, "#cp-confirmer-numero") && await page.inputValue("#cp-tel") === "0197000011",
    "le bouton mène à la confirmation, le numéro déjà dans le champ");
  ok(!(await page.$("#cp-renoncer")), "sans « Annuler » : il est déjà connecté, la flèche suffit");
  await page.click("#cp-envoyer");
  await page.waitForTimeout(700);
  const garde0 = await garde(page);
  ok((note.put[0] || {}).auth === "Bearer " + garde0.access_token,
    "le code part au nom de la session du téléphone");
  sansErreur(erreurs);
  await ctx.close();
}
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true, session: {}, panier: true });
  await aller(page, "#/commande", 2400);
  ok(await visible(page, "#cp-confirmer-numero") && !/Adresse de livraison/.test(await page.innerText("#vue")),
    "avant de commander : la confirmation, pas le formulaire");
  await page.click("#cp-envoyer");
  await page.waitForTimeout(700);
  await taperCode(page, "777777");
  await page.waitForTimeout(2200);
  ok(note.verify.length === 1 && /Adresse de livraison/.test(await page.innerText("#vue")) &&
     !(await page.$("#cp-confirmer-numero")),
    "le numéro confirmé, la commande reprend d'elle-même");
  ok(await page.evaluate(() => JSON.parse(localStorage.getItem("bizzoo-panier") || "[]").length) === 1,
    "le panier n'a pas bougé");
  sansErreur(erreurs);
  await ctx.close();
}
{
  const { page, ctx, erreurs } = await ouvrir({ sms: true, session: { sub: MOI, phone: "2290197121596", email: "" },
    panier: true });
  await aller(page, "#/commande", 2400);
  ok(!(await page.$("#cp-confirmer-numero")) && /Adresse de livraison/.test(await page.innerText("#vue")),
    "un compte au numéro confirmé commande directement");
  await aller(page, "#/compte", 1800);
  ok(!(await page.$("#cp-numero-requis")), "et Mon compte ne lui demande rien");
  sansErreur(erreurs);
  await ctx.close();
}

titre("7. Le SMS fermé ou incertain : on n'enferme personne");
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: false });
  await aller(page, "#/connexion");
  ok(await visible(page, "#cp-entrer") && !(await page.$("#cp-envoyer")),
    "SMS fermé : l'e-mail revient devant, sans le numéro");
  await page.fill("#cp-email", "awa@essai.bj");
  await page.fill("#cp-mdp", "secret-essai");
  await page.click("#cp-entrer");
  await page.waitForTimeout(1500);
  ok(await connecte(page) && !(await page.$("#cp-confirmer-numero")) && note.put.length === 0,
    "SMS fermé : le mot de passe suffit, comme avant");
  sansErreur(erreurs);
  await ctx.close();
}
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: "panne" });
  await aller(page, "#/connexion");
  ok(await visible(page, "#cp-envoyer") && !!(await page.$('a[href="#/connexion-email"]')),
    "SMS incertain : le numéro reste montré, l'e-mail derrière son lien");
  await aller(page, "#/connexion-email");
  await page.fill("#cp-email", "awa@essai.bj");
  await page.fill("#cp-mdp", "secret-essai");
  await page.click("#cp-entrer");
  await page.waitForTimeout(1500);
  ok(await connecte(page) && !(await page.$("#cp-confirmer-numero")) && note.put.length === 0,
    "SMS incertain : on ne retient personne dehors sur une réponse qu'on n'a pas");
  sansErreur(erreurs);
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec." : "\nTous les constats sont bons.");
process.exit(echecs ? 1 : 0);
