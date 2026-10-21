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
      access_token: jwt({ sub: o.session.sub || ANCIEN, email: "email" in o.session ? o.session.email : "awa@essai.bj",
        phone: o.session.phone || "", session_id: "a1000000-0000-4000-8000-000000000001" }),
      refresh_token: "r", expire_a: Date.now() + 3600000,
      email: "email" in o.session ? o.session.email : "awa@essai.bj", tel: o.session.phone || "",
    } : null,
    panier: !!o.panier,
  });

  const note = { otp: [], verify: [], put: [], token: [], patch: [], profils: [], clients: [], rattacher: 0,
    signup: [], resend: [], logout: [] };
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
    if (chemin === "resend") { note.resend.push(corps); return json(200, {}); }
    if (chemin === "signup") {
      note.signup.push(corps);
      if (o.dejaInscrit) return json(422, { code: 422, error_code: "user_already_exists", msg: "User already registered" });
      return json(200, { id: MOI, phone: String(corps.phone || "").replace(/\D/g, ""), identities: [{ id: "x" }] });
    }
    if (chemin === "user" && req.method() === "PUT") {
      note.put.push({ corps, auth: req.headers()["authorization"] || "" });
      if (corps.email) {
        return json(200, { id: MOI, email: o.emailEnAttente ? "" : corps.email,
          new_email: o.emailEnAttente ? corps.email : undefined, phone: "2290197121596" });
      }
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
    if (chemin.startsWith("token") && corps.phone) {
      note.token.push(corps);
      if (corps.password !== "secret-essai") {
        return json(400, { code: 400, error_code: "invalid_credentials", msg: "Invalid login credentials" });
      }
      if (o.nonConfirme) return json(400, { error: "invalid_grant", error_description: "Phone not confirmed" });
      return json(200, {
        access_token: jwt({ sub: MOI, phone: corps.phone.replace(/\D/g, ""), email: "",
          session_id: "d4000000-0000-4000-8000-000000000004" }),
        token_type: "bearer", expires_in: 3600, refresh_token: "rm",
        user: { id: MOI, phone: corps.phone.replace(/\D/g, ""), email: "",
          phone_confirmed_at: "2026-02-01T10:00:00Z" },
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
    if (chemin === "logout") {
      note.logout.push({ portee: url.searchParams.get("scope") || "", auth: req.headers()["authorization"] || "" });
      return route.fulfill({ status: 204, body: "" });
    }
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

titre("1. « Se connecter » : le numéro et le mot de passe");
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true, fiche: { id: MOI, nom: "Awa",
    tel: "0197121596", indicatif: "229", tel_verifie: true, type_compte: "client",
    revendeur_etat: "aucune", adresse: "Cotonou" } });
  await aller(page, "#/connexion");
  ok(await visible(page, "#cp-tel") && await visible(page, "#cp-mdp-tel") && await visible(page, "#cp-envoyer"),
    "le numéro et le mot de passe sont devant");
  ok(!(await page.$("#cp-email")), "pas d'e-mail à l'écran");
  ok(!!(await page.$('a[href="#/connexion-email"]')), "l'e-mail a son lien, en secours");
  ok(!!(await page.$('a[href="#/mot-de-passe"]')), "« Mot de passe oublié » est là");
  ok(!!(await page.$('a[href="#/inscription"]')), "« Créer mon compte » reste");

  await page.click("#cp-envoyer");
  await page.waitForTimeout(400);
  ok(note.token.length === 0 && /Tapez votre numéro/.test(await toasts(page)),
    "sans numéro, rien ne part");
  await page.fill("#cp-tel", "01 97 12 15 96");
  await page.click("#cp-envoyer");
  await page.waitForTimeout(400);
  ok(note.token.length === 0 && /mot de passe/.test(await toasts(page)),
    "sans mot de passe, rien ne part");

  await page.fill("#cp-mdp-tel", "mauvais");
  await page.click("#cp-envoyer");
  await page.waitForTimeout(700);
  ok(note.token.length === 1 && note.otp.length === 0 &&
     /Numéro ou mot de passe incorrect/.test(await toasts(page)),
    "mauvais mot de passe : « Numéro ou mot de passe incorrect », et AUCUN code ne part");

  await page.fill("#cp-mdp-tel", "secret-essai");
  await page.click("#cp-envoyer");
  await page.waitForTimeout(800);
  const t = note.token[1] || {};
  ok(t.phone === "+2290197121596" && t.password === "secret-essai" && !t.email,
    "le mot de passe se vérifie avec le numéro, au format de GoTrue (" + t.phone + ")");
  /* (3.59.0) PLUS DE CODE À CHAQUE CONNEXION : le numéro est confirmé
     depuis l'inscription, le mot de passe suffit. */
  titre("2. Numéro déjà confirmé : il entre, sans code");
  await page.waitForTimeout(800);
  ok(note.otp.length === 0 && note.verify.length === 0, "aucun code ne part, aucun n'est demandé");
  ok(!(await page.$("#cp-code")), "pas d'écran de code");
  const s = await garde(page);
  ok(!!s && s.tel === "2290197121596", "la session du mot de passe est gardée, avec son numéro");
  ok(note.logout.length === 0, "et elle n'est pas fermée");
  ok(await hash(page) === "#/compte" && /Bonjour/.test(await toasts(page)),
    "le client entre : « Bonjour ! », et Mon compte");
  ok(!/Code incorrect/.test(await toasts(page)), "aucun « code incorrect » après coup");
  sansErreur(erreurs);
  await ctx.close();
}

titre("3. Mot de passe oublié (ou jamais choisi) : le code, puis le mot de passe");
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true, verifie: { nouveau: false },
    fiche: { id: MOI, nom: "", tel: "0197121596", indicatif: "229", tel_verifie: true,
      type_compte: "client", revendeur_etat: "aucune", adresse: "Cotonou, Akpakpa" } });
  await aller(page, "#/connexion");
  await page.click("#cp-oubli");
  await page.waitForTimeout(900);
  ok(await visible(page, "#cp-oubli-tel") && await visible(page, "#cp-email"),
    "deux chemins : le numéro d'abord, l'e-mail ensuite");
  await page.fill("#cp-tel", "0197121596");
  await page.click("#cp-oubli-envoyer");
  await page.waitForTimeout(700);
  ok((note.otp[0] || {}).create_user === false && note.token.length === 0,
    "un code part, sans mot de passe et sans créer de compte");
  await taperCode(page, "111111");
  await page.waitForTimeout(1500);
  ok(await visible(page, "#cp-choisir-mdp"), "le code passé, on choisit son mot de passe");
  await page.fill("#cp-nouveau", "nouveau-mdp");
  await page.fill("#cp-encore", "autre-chose");
  await page.click("#cp-changer");
  await page.waitForTimeout(300);
  ok(!note.put.length && /pas identiques/.test(await toasts(page)), "deux saisies différentes : rien ne part");
  await page.fill("#cp-encore", "nouveau-mdp");
  await page.click("#cp-changer");
  await page.waitForTimeout(1200);
  ok(!!(note.put[0] || {}).corps && note.put[0].corps.password === "nouveau-mdp",
    "le mot de passe s'enregistre sur la session du code");
  ok(await visible(page, "#cp-nommer"), "un compte sans nom le donne ensuite");
  await page.fill("#cp-nom", "Awa Dossou");
  await page.click("#cp-nommer-ok");
  await page.waitForTimeout(1200);
  const p = note.patch[0] || {};
  ok(p.nom === "Awa Dossou" && Object.keys(p).sort().join(",") === "maj_le,nom",
    "seul le nom s'écrit — l'adresse déjà donnée ne s'efface pas (" + Object.keys(p).join(",") + ")");
  ok(await hash(page) === "#/compte", "et il arrive dans Mon compte");
  sansErreur(erreurs);
  await ctx.close();
}

titre("4. « Créer mon compte » : le nom, le numéro, un mot de passe, le code");
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true, verifie: { nouveau: true },
    fiche: { id: MOI, nom: "Koffi Mensah", tel: "0161000022", indicatif: "229", tel_verifie: true,
      type_compte: "client", revendeur_etat: "aucune", adresse: "" } });
  await aller(page, "#/inscription");
  ok(!(await page.$("#cp-email")), "pas d'e-mail exigé");
  ok(await visible(page, "#cp-nom") && await visible(page, "#cp-tel") &&
     await visible(page, "#cp-mdp-nouveau") && await visible(page, "#cp-creer-tel"),
    "le nom, le numéro, le mot de passe, et « Créer mon compte »");

  await page.fill("#cp-tel", "0161000022");
  await page.click("#cp-creer-tel");
  await page.waitForTimeout(300);
  ok(note.signup.length === 0 && /Votre nom/.test(await toasts(page)), "sans nom, rien ne part");
  await page.fill("#cp-nom", "Koffi Mensah");
  await page.click("#cp-creer-tel");
  await page.waitForTimeout(300);
  ok(note.signup.length === 0 && /six caractères/.test(await toasts(page)), "sans mot de passe, rien ne part");
  await page.fill("#cp-mdp-nouveau", "secret-essai");
  await page.fill("#cp-mdp-encore", "secret-autre");
  await page.click("#cp-creer-tel");
  await page.waitForTimeout(300);
  ok(note.signup.length === 0 && /pas identiques/.test(await toasts(page)),
    "deux mots de passe différents : rien ne part");
  await page.fill("#cp-mdp-encore", "secret-essai");

  await page.click('[data-type="revendeur"]');
  await page.click("#cp-creer-tel");
  await page.waitForTimeout(300);
  ok(note.signup.length === 0 && /quel commerce/.test(await toasts(page)),
    "« Pour revendre » demande d'abord quel commerce");
  await page.fill("#cp-message", "Boutique Mensah, accessoires téléphone");
  await page.fill("#cp-pos-adresse", "Dantokpa, face à la pharmacie");
  await page.click("#cp-creer-tel");
  await page.waitForTimeout(300);
  ok(note.signup.length === 0 && /Activez votre position/.test(await toasts(page)),
    "« Pour revendre » sans position du téléphone : rien ne part");
  await page.evaluate(() => {
    Object.defineProperty(navigator, "geolocation", { configurable: true, value: {
      getCurrentPosition: (ok) => ok({ coords: { latitude: 6.3561, longitude: 2.4334, accuracy: 15 } }) } });
  });
  await page.click("#cp-pos-relever");
  await page.waitForTimeout(300);
  await page.click("#cp-creer-tel");
  await page.waitForTimeout(700);
  const e = note.signup[0] || {};
  ok(e.phone === "+2290161000022" && e.password === "secret-essai" && !e.email &&
     e.data && e.data.nom === "Koffi Mensah" && e.data.compte === "client",
    "l'inscription part : numéro, mot de passe, nom, « compte: client » — sans e-mail");
  ok(note.otp.length === 0 && await visible(page, "#cp-code"),
    "le code de confirmation vient de l'inscription elle-même");
  await page.click("#cp-renvoyer");
  await page.waitForTimeout(400);
  ok((note.resend[0] || {}).type === "sms" && note.resend[0].phone === "+2290161000022",
    "« Renvoyer le code » redemande celui de l'inscription");
  await taperCode(page, "222222");
  await page.waitForTimeout(1800);
  ok((note.verify[0] || {}).type === "sms", "le code se vérifie");
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
  const { page, ctx, erreurs } = await ouvrir({ sms: true, dejaInscrit: true });
  await aller(page, "#/inscription");
  await page.fill("#cp-nom", "K. Mensah");
  await page.fill("#cp-tel", "0161000022");
  await page.fill("#cp-mdp-nouveau", "secret-essai");
  await page.fill("#cp-mdp-encore", "secret-essai");
  await page.click("#cp-creer-tel");
  await page.waitForTimeout(800);
  ok(/déjà un compte BIZZOO/.test(await toasts(page)) && !(await page.$("#cp-code")),
    "on le dit, et on l'envoie se connecter — pas d'écran de code");
  ok(!/avec cet e-mail/.test(await toasts(page)), "le message parle du numéro, pas d'un e-mail");
  sansErreur(erreurs);
  await ctx.close();
}

titre("4 ter. Le mot de passe est juste, le numéro pas encore confirmé");
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true, nonConfirme: true });
  await aller(page, "#/connexion");
  await page.fill("#cp-tel", "0161000022");
  await page.fill("#cp-mdp-tel", "secret-essai");
  await page.click("#cp-envoyer");
  await page.waitForTimeout(800);
  ok(note.otp.length === 0 && (note.resend[0] || {}).type === "sms" && await visible(page, "#cp-code"),
    "le code de confirmation est redemandé — pas un refus « mot de passe incorrect »");
  ok(!/incorrect/.test(await toasts(page)), "aucun « incorrect » affiché");
  sansErreur(erreurs);
  await ctx.close();
}

titre("4 quater. Mon compte : ajouter son e-mail de secours, changer son mot de passe");
for (const enAttente of [false, true]) {
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true, emailEnAttente: enAttente,
    session: { sub: MOI, phone: "2290197121596", email: "" },
    fiche: { id: MOI, nom: "Awa", tel: "0197121596", indicatif: "229", tel_verifie: true,
      type_compte: "client", revendeur_etat: "aucune", adresse: "Cotonou" } });
  await aller(page, "#/compte", 1800);
  ok(await visible(page, "#cp-connexion") && /facultatif/.test(await page.innerText("#cp-connexion")),
    "la carte « Mes accès » propose l'e-mail, facultatif");
  await page.fill("#cp-email-secours", "pas-une-adresse");
  await page.click("#cp-email-ajouter");
  await page.waitForTimeout(400);
  ok(!note.put.length && /pas valide/.test(await toasts(page)), "une adresse mal formée ne part pas");
  await page.fill("#cp-email-secours", "Awa@Essai.bj");
  await page.click("#cp-email-ajouter");
  await page.waitForTimeout(1500);
  const put = note.put[0] || { corps: {} };
  ok(put.corps.email === "awa@essai.bj" && /Bearer /.test(put.auth),
    "l'adresse part, en minuscules, avec la session du client");
  if (!enAttente) {
    ok(/E-mail enregistré/.test(await toasts(page)) &&
       /awa@essai\.bj/.test(await page.innerText("#cp-connexion")),
      "appliquée tout de suite : la carte la montre");
    ok((await garde(page)).email === "awa@essai.bj", "et la session la garde");
  } else {
    ok(/Ouvrez le message envoyé à/.test(await toasts(page)),
      "un lien à confirmer : on le dit, au lieu de crier victoire");
  }
  await page.click("#cp-mdp-changer");
  await page.waitForTimeout(400);
  ok(await visible(page, "#cp-choisir-mdp"), "« Changer mon mot de passe » ouvre le formulaire");
  sansErreur(erreurs);
  await ctx.close();
}

titre("5. L'ancien compte e-mail confirme son numéro avant d'entrer");
{
  const { page, ctx, erreurs, note } = await ouvrir({ sms: true });
  await aller(page, "#/connexion");
  await page.click('a[href="#/connexion-email"]');
  await page.waitForTimeout(900);
  ok(await visible(page, "#cp-email") && /sans code/.test(await page.innerText("#vue")),
    "la porte e-mail explique ce qu'elle est : le secours, sans code");
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
