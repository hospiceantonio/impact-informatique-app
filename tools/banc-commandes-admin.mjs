/* =========================================================
   L'écran Commandes de l'admin : serré, et rien de perdu
   =========================================================
   LE DÉFAUT QU'ON DÉFEND ICI. Une commande de trois articles prenait
   tout un écran de téléphone (685 px) : l'état et son bouton, posés À
   CÔTÉ du nom, lui prenaient la moitié de la largeur, et « Chargeur
   rapide USB-C 25 W Samsung d'origine » se cassait mot par mot sur
   sept lignes. Les montants se coupaient en « 142 000 » / « FCFA ». Un
   bandeau « Payée — confirmée par KkiaPay » et deux grands boutons
   s'empilaient sur chaque carte — et « KkiaPay » était faux quand
   l'enseigne encaisse par FeexPay.

   Six choses à prouver :

     1. RIEN NE DÉBORDE, du plus petit téléphone (320 px) à l'ordinateur ;
     2. UN NOM D'ARTICLE TIENT SUR UNE LIGNE, et se déplie d'un appui ;
        un montant ne se coupe jamais ;
     3. LES CARTES SONT SERRÉES : hauteurs bornées, libellés à leur
        taille, pas de bandeau « Payée », des boutons compacts ;
     4. L'AGRÉGATEUR NOMMÉ EST LE BON : FeexPay, KkiaPay, ou la main
        de celui qui a confirmé ;
     5. RIEN N'A DISPARU : numéro, statut, montant, client, appel,
        WhatsApp, adresse, note, code, référence, état, geste suivant,
        confirmation du client, « Confier », « Revendeur », sa part ;
     6. À L'ORDINATEUR, le client et les articles côte à côte, et le
        bouton à sa taille.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-commandes-admin.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-commandes-admin.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const MOI = "22222222-2222-2222-2222-222222222222";
const BOU = [{ id: "bou_info", nom: "Impact Informatique", secteur: "Informatique", categorie_id: "cat_h",
  icone: "portable", couleur: "#0047D9", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }];
const il = (min) => new Date(Date.now() - min * 60000).toISOString();
const L = (id, cmd, nom, code, ref, prix, q, etat, conf) => ({ id, commande_id: cmd,
  boutique_id: "bou_info", produit_id: "p_" + id, nom, code, reference: ref, prix, quantite: q, etat,
  cree_le: il(30), confirme_le: conf || null });
const C = (o) => ({ note: "", devise: "FCFA", transaction_id: "tx", fournisseur_ref: "", confirme_par: "",
  remarque: "", transaction_annoncee: "", revendeur: false, client_indicatif: "229", ...o });
const LONG = "Ordinateur portable HP 15.6 pouces Intel Core i5 8 Go RAM 512 Go SSD Windows 11";
const CMD = [
  /* Payée par FeexPay : elle porte la référence que FeexPay a donnée. */
  C({ id: "c21", numero: "BZ-000021", fournisseur_ref: "FXP-9001", client_nom: "Koffi Ahouansou",
    client_tel: "0197000000", client_adresse: "Cotonou, Fidjrossè, derrière la pharmacie Sainte Rita",
    note: "Merci d'appeler avant de passer.", total: 319500, etat: "payee", paye_le: il(11),
    cree_le: il(12), commande_lignes: [
      L("l1", "c21", LONG, "100061", "HP-15-i5", 299000, 1, "nouvelle"),
      L("l2", "c21", "Souris sans fil Logitech M185 gris", "100062", "", 7500, 2, "vue"),
      L("l3", "c21", "Clé USB SanDisk Ultra 64 Go USB 3.0", "100063", "SDCZ48", 5500, 1, "nouvelle"),
    ] }),
  /* Revendeur, prête à partir : « Confier » doit s'offrir. */
  C({ id: "c20", numero: "BZ-000020", fournisseur_ref: "FXP-9000", client_nom: "Mireille Dossou",
    client_tel: "0166554433", client_adresse: "Abomey-Calavi, Tankpè", revendeur: true, total: 142000,
    etat: "payee", paye_le: il(26 * 60), cree_le: il(26 * 60 + 5), commande_lignes: [
      L("l4", "c20", "Imprimante multifonction Canon PIXMA G3411 à réservoirs rechargeables Wi-Fi",
        "100070", "", 142000, 1, "preparee"),
    ] }),
  /* Passée par KkiaPay (pas de référence FeexPay), partagée avec une
     autre boutique : sa part, « sur » le total. */
  C({ id: "c18", numero: "BZ-000018", client_nom: "Awa Soglo", client_tel: "0191223344",
    client_adresse: "Porto-Novo, Ouando", total: 64000, etat: "payee", paye_le: il(3 * 60),
    cree_le: il(3 * 60 + 2), commande_lignes: [
      L("l5", "c18", "Casque Bluetooth JBL Tune 510BT pliable", "100081", "", 29000, 1, "en_livraison"),
    ] }),
  /* Confirmée à la main, remise, et le client a confirmé la réception. */
  C({ id: "c17", numero: "BZ-000017", confirme_par: "chef@bizzoo.bj", client_nom: "Jean Hounkpè",
    client_tel: "0152334455", client_adresse: "Cotonou, Cadjèhoun", total: 24000, etat: "payee",
    paye_le: il(3 * 24 * 60), cree_le: il(3 * 24 * 60 + 3), commande_lignes: [
      L("l6", "c17", "Chargeur rapide USB-C 25 W Samsung d'origine", "100090", "", 12000, 2, "remise",
        il(2 * 24 * 60)),
    ] }),
];
const ATTENTE = C({ id: "c22", numero: "BZ-000022", client_nom: "Rodrigue Agbo", client_tel: "0161000000",
  client_adresse: "Cotonou, Akpakpa", total: 45000, etat: "a_payer", cree_le: il(40),
  transaction_annoncee: "TX-88213", commande_lignes: [
    L("l7", "c22", "Disque dur externe Seagate 1 To USB 3.0", "100095", "", 45000, 1, "nouvelle")] });

async function ouvrir({ largeur = 390, hauteur = 900, role = "administrateur" } = {}) {
  const ctx = await nav.newContext({ viewport: { width: largeur, height: hauteur } });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((moi) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: moi }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: "chef@impact.bj" }));
  }, MOI);
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("profils")) return d([{ id: MOI, email: "chef@impact.bj", role, actif: true,
      peut_modifier_produits: true, boutique_id: role === "superadministrateur" ? null : "bou_info" }]);
    if (c.startsWith("commandes")) return d(role === "superadministrateur" ? [ATTENTE, ...CMD] : CMD);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  await page.evaluate(() => { location.hash = "#/commandes"; });
  await page.waitForTimeout(1500);
  return { page, ctx, erreurs };
}

/* Tout ce qu'une carte montre, mesuré sur l'écran. */
const lire = (page) => page.evaluate(() => {
  const lignesDe = (el) => {
    const r = el.getBoundingClientRect();
    const lh = parseFloat(getComputedStyle(el).lineHeight) || parseFloat(getComputedStyle(el).fontSize) * 1.4;
    return Math.round(r.height / lh);
  };
  const px = (el) => el ? parseFloat(getComputedStyle(el).fontSize) : 0;
  return {
    deborde: document.documentElement.scrollWidth > document.documentElement.clientWidth + 1,
    cartes: [...document.querySelectorAll(".cmd-carte")].map((c) => ({
      id: c.dataset.commande,
      texte: c.innerText,
      hauteur: Math.round(c.getBoundingClientRect().height),
      numero: (c.querySelector(".cmd-numero") || {}).textContent || "",
      statut: [...c.querySelectorAll(".cmd-titre .badge")].map((b) => b.textContent.trim()),
      meta: (c.querySelector(".cmd-meta") || {}).textContent || "",
      bandeaux: [...c.querySelectorAll(".cmd-etat")].map((b) => b.textContent.trim()),
      montantLignes: lignesDe(c.querySelector(".cmd-montant")),
      part: (c.querySelector(".cmd-part") || {}).textContent || "",
      partLignes: c.querySelector(".cmd-part") ? lignesDe(c.querySelector(".cmd-part")) : 1,
      tel: (c.querySelector(".cmd-client-tel") || {}).getAttribute
        ? c.querySelector(".cmd-client-tel").getAttribute("href") : "",
      whatsapp: (c.querySelector(".cmd-wa") || {}).getAttribute ? c.querySelector(".cmd-wa").getAttribute("href") : "",
      waEtiquette: (c.querySelector(".cmd-wa") || {}).getAttribute
        ? c.querySelector(".cmd-wa").getAttribute("aria-label") : "",
      lignes: [...c.querySelectorAll(".cmd-ligne")].map((l) => {
        const nom = l.querySelector(".cmd-ligne-nom");
        return {
          nom: nom.textContent, titre: nom.getAttribute("title") || "",
          lignes: lignesDe(nom), tronque: nom.scrollWidth > nom.clientWidth + 1,
          prixLignes: lignesDe(l.querySelector(".cmd-ligne-prix")),
          prix: l.querySelector(".cmd-ligne-prix").textContent,
          code: (l.querySelector(".code-produit") || {}).textContent || "",
          ref: (l.querySelector(".cmd-ref") || {}).textContent || "",
          etat: (l.querySelector(".cmd-ligne-etat .badge") || {}).textContent || "",
          geste: (l.querySelector("[data-avancer]") || {}).textContent || "",
          confirme: (l.querySelector(".cmd-confirme") || {}).textContent || "",
        };
      }),
      confier: !!c.querySelector("[data-confier]"),
      boutonConfier: c.querySelector("[data-confier]")
        ? (() => { const b = c.querySelector("[data-confier]").getBoundingClientRect();
            return { largeur: Math.round(b.width), hauteur: Math.round(b.height),
              police: px(c.querySelector("[data-confier]")) }; })() : null,
      tailles: { numero: px(c.querySelector(".cmd-numero")), montant: px(c.querySelector(".cmd-montant")),
        nom: px(c.querySelector(".cmd-ligne-nom")) },
      cotes: (() => {
        const cl = c.querySelector(".cmd-client"), li = c.querySelector(".cmd-lignes");
        if (!cl || !li) return null;
        const a = cl.getBoundingClientRect(), b = li.getBoundingClientRect();
        return { cote: a.right <= b.left + 1 && Math.abs(a.top - b.top) < 40 };
      })(),
    })),
  };
});

/* ------------------------------------------------------------------ */
titre("1. Rien ne déborde, du plus petit téléphone à l'ordinateur");
for (const largeur of [320, 360, 390, 768, 1280]) {
  const { page, ctx, erreurs } = await ouvrir({ largeur });
  const m = await lire(page);
  ok(m.cartes.length === 4 && !m.deborde, largeur + " px : quatre commandes, sans défilement de côté");
  if (largeur === 320) {
    /* LE PLUS SERRÉ : titre, badge et montant se disputent 260 px. C'est
       le titre qui passe à la ligne, jamais le montant. */
    ok(m.cartes.every((c) => c.montantLignes === 1 && c.partLignes === 1),
      "320 px : aucun montant coupé (" + m.cartes.map((c) => c.montantLignes).join(", ") + ")");
    ok(m.cartes.every((c) => c.lignes.every((l) => l.prixLignes === 1)),
      "320 px : aucun prix d'article coupé");
  }
  ok(!erreurs.length, largeur + " px : sans erreur JavaScript" + (erreurs.length ? " : " + erreurs.join(" | ") : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("2. Un nom d'article tient sur une ligne, et se déplie d'un appui");
{
  const { page, ctx } = await ouvrir();
  const m = await lire(page);
  const lignes = m.cartes.flatMap((c) => c.lignes);
  ok(lignes.every((l) => l.lignes === 1), "chaque nom tient sur une ligne (" +
    lignes.map((l) => l.lignes).join(", ") + ")");
  const long = lignes.find((l) => l.nom === LONG);
  ok(long && long.tronque && long.titre === LONG, "le plus long est tronqué, et garde son nom entier en titre");
  const avant = await page.evaluate(() => document.querySelector(".cmd-ligne-nom").getBoundingClientRect().height);
  await page.click(".cmd-ligne-nom");
  const ouvert = await page.evaluate(() => {
    const n = document.querySelector(".cmd-ligne-nom");
    return { etat: n.getAttribute("aria-expanded"), hauteur: n.getBoundingClientRect().height };
  });
  ok(ouvert.etat === "true" && ouvert.hauteur > avant * 1.5, "un appui le déplie en entier");
  await page.click(".cmd-ligne-nom");
  const ferme = await page.evaluate(() => {
    const n = document.querySelector(".cmd-ligne-nom");
    return { etat: n.getAttribute("aria-expanded"), hauteur: n.getBoundingClientRect().height };
  });
  ok(ferme.etat === "false" && Math.abs(ferme.hauteur - avant) < 2, "un second le replie");
  ok(m.cartes.every((c) => c.montantLignes === 1), "aucun montant ne se coupe en « 142 000 » / « FCFA »");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("3. Des cartes serrées, des libellés à leur taille");
{
  const { page, ctx } = await ouvrir();
  const m = await lire(page);
  const par = (n) => m.cartes.find((c) => c.numero === n) || { hauteur: 9999, tailles: {} };
  /* Avant : 685 px pour trois articles, 470 à 560 pour un seul. */
  ok(par("BZ-000021").hauteur <= 460, "trois articles : au plus 460 px (" + par("BZ-000021").hauteur + ")");
  ok(m.cartes.filter((c) => c.lignes.length === 1).every((c) => c.hauteur <= 340),
    "un article : au plus 340 px (" + m.cartes.filter((c) => c.lignes.length === 1).map((c) => c.hauteur).join(", ") + ")");
  const t = par("BZ-000021").tailles;
  ok(t.numero <= 14 && t.montant <= 16 && t.nom <= 13,
    "numéro ≤ 14 px, montant ≤ 16 px, nom d'article ≤ 13 px (" + [t.numero, t.montant, t.nom].join(" / ") + ")");
  /* LE BANDEAU « PAYÉE » SUR CHAQUE CARTE : le titre de la pile le dit
     déjà. Le paiement tient sur la ligne de l'heure. */
  ok(m.cartes.every((c) => !c.bandeaux.some((b) => /^Payée/.test(b))), "plus de bandeau « Payée » sur les cartes payées");
  const b = par("BZ-000020").boutonConfier;
  ok(b && b.hauteur <= 44 && b.police <= 14, "« Confier » en bouton compact (" + (b ? b.hauteur + " px, " + b.police + " px" : "absent") + ")");
  const confirme = m.cartes.flatMap((c) => c.lignes).find((l) => l.confirme);
  ok(confirme && !/\b20\d\d\b/.test(confirme.confirme),
    "la date de réception, courte : pas d'année pour cette année (" + (confirme ? confirme.confirme.trim() : "") + ")");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("4. L'agrégateur nommé est le bon");
{
  const { page, ctx } = await ouvrir();
  const m = await lire(page);
  const meta = (n) => (m.cartes.find((c) => c.numero === n) || {}).meta || "";
  /* LE DÉFAUT D'ORIGINE : « confirmée par KkiaPay » sur TOUTES les
     commandes, quand l'enseigne encaisse par FeexPay. */
  ok(/payée par FeexPay/.test(meta("BZ-000021")), "référence FeexPay : « payée par FeexPay » (" + meta("BZ-000021").trim() + ")");
  ok(/payée par KkiaPay/.test(meta("BZ-000018")), "sans elle : « payée par KkiaPay »");
  ok(/confirmée à la main par chef@bizzoo\.bj/.test(meta("BZ-000017")), "confirmée à la main : on dit par qui");
  await ctx.close();
}
{
  const { page, ctx } = await ouvrir({ role: "superadministrateur" });
  const m = await lire(page);
  const c = m.cartes.find((x) => x.numero === "BZ-000022") || { bandeaux: [], texte: "" };
  ok(c.bandeaux.some((b) => /non confirmé par KkiaPay/.test(b)),
    "paiement à vérifier : le bandeau reste, il nomme l'agrégateur de la commande");
  ok(/Confirmer le paiement à la main/.test(c.texte) && /TX-88213/.test(c.texte),
    "et le superadministrateur peut confirmer, la transaction annoncée sous les yeux");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("5. Rien n'a disparu");
{
  const { page, ctx } = await ouvrir();
  const m = await lire(page);
  const c21 = m.cartes.find((c) => c.numero === "BZ-000021");
  const c20 = m.cartes.find((c) => c.numero === "BZ-000020");
  const c18 = m.cartes.find((c) => c.numero === "BZ-000018");
  const c17 = m.cartes.find((c) => c.numero === "BZ-000017");
  ok(c21 && c21.statut.includes("Payé") && /319 500 FCFA/.test(c21.texte), "numéro, statut et montant");
  ok(c21 && /Koffi Ahouansou/.test(c21.texte) && /^tel:/.test(c21.tel) &&
    /Fidjrossè/.test(c21.texte) && /Merci d'appeler/.test(c21.texte),
    "le client : nom, appel, adresse, et sa note");
  /* WHATSAPP, À CÔTÉ DU NUMÉRO, avec le récapitulatif tout rédigé. */
  ok(c21 && /wa\.me|whatsapp/.test(c21.whatsapp) && decodeURIComponent(c21.whatsapp).includes("BZ-000021") &&
    /WhatsApp/.test(c21.waEtiquette || ""), "WhatsApp : le message part avec le récapitulatif de la commande");
  const l1 = c21 ? c21.lignes[0] : {};
  ok(l1.code === "100061" && /HP-15-i5/.test(l1.ref) && l1.etat === "Nouvelle" && l1.geste === "Marquer vue" &&
    /299 000 FCFA/.test(l1.prix), "un article : code, référence, prix, état et geste suivant");
  ok(await page.evaluate(() => [...document.querySelectorAll(".cmd-quantite")].map((q) => q.textContent).join(","))
    === "1×,2×,1×,1×,1×,2×", "les quantités");
  ok(c20 && c20.confier && /Revendeur/.test(c20.meta), "prête à partir : « Confier à un livreur », et « Revendeur »");
  ok(c21 && !c21.confier, "pas de « Confier » tant que rien n'est préparé");
  ok(c18 && /sur 64 000 FCFA/.test(c18.part), "une commande partagée : sa part, « sur » le total");
  ok(c17 && /Reçu confirmé par le client/.test(c17.lignes[0].confirme), "la réception confirmée par le client");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("6. À l'ordinateur : côte à côte, et un bouton à sa taille");
{
  const { page, ctx } = await ouvrir({ largeur: 1280 });
  const m = await lire(page);
  ok(m.cartes.every((c) => c.cotes && c.cotes.cote), "le client à gauche, les articles à droite, sur chaque carte");
  ok(m.cartes.every((c) => c.hauteur <= 300), "aucune carte au-delà de 300 px (" + m.cartes.map((c) => c.hauteur).join(", ") + ")");
  const b = (m.cartes.find((c) => c.numero === "BZ-000020") || {}).boutonConfier;
  ok(b && b.largeur <= 400, "« Confier à un livreur » à sa taille, pas en barre de toute la largeur (" +
    (b ? b.largeur + " px" : "absent") + ")");
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec.\n" : "\nL'écran des commandes tient ✔\n");
process.exit(echecs ? 1 : 0);
