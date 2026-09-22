/* =========================================================
   Les huit écrans de la DA corrigée
   =========================================================
   CE QUE CE BANC GARDE. La DA a changé la STRUCTURE de
   l'application, pas seulement ses couleurs : une barre du bas
   à quatre onglets, des écrans de parcours qui n'en ont pas et
   portent une action en bas, des écrans nouveaux. Ce sont des
   règles qui se défont sans bruit — un onglet qui revient, une
   action qui survit à son écran — et qu'aucun autre banc ne voit.

   ET CE QUE LA MAQUETTE MONTRAIT SANS QUE CE SOIT VRAI. Elle
   annonce « 5 000 FCFA » de livraison, « un e-mail » à la
   confirmation, « Orange Money » et « Carte bancaire » au
   paiement. Rien de cela n'existe ici : le banc vérifie que
   l'application ne l'invente pas en recopiant le dessin.

   Sept choses à prouver :

     1. LA BARRE A QUATRE ONGLETS, ceux de la DA ;
     2. ELLE DISPARAÎT SUR LES ÉCRANS DE PARCOURS, et l'action
        du bas prend sa place — sans survivre à son écran ;
     3. L'ACCUEIL SUIT L'ORDRE DE LA DA, et « Nos boutiques »
        existe, avec des filtres qui ne mentent pas ;
     4. LA FICHE BOUTIQUE : trois onglets, et « Paiement
        sécurisé » seulement quand le paiement est ouvert ;
     5. LE PANIER : aucun frais de livraison inventé ;
     6. LE PAIEMENT : les vrais opérateurs, et un choix qui se
        lit ;
     7. LA CONFIRMATION : seulement quand c'est vrai, et sans
        promettre d'e-mail.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-da-ecrans.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const CATS = [
  ["cat_mode", "Mode & Accessoires", "tshirt"],
  ["cat_hightech", "Électronique & Informatique", "portable"],
  ["cat_maison", "Maison & Déco", "maison"],
  ["cat_beaute", "Beauté & Santé", "sante"],
].map(([id, nom, icone], i) => ({ id, nom, icone, couleur: "#0047D9", en_avant: true,
  ordre: i + 1, boutique_id: null, sous_categories: [{ id: "sc_" + id, nom: "Tout", ordre: 1 }] }));

/* Trois boutiques : deux notées, une sans aucun avis. C'est celle-là
   qui dit si « Top » range les « sans avis » parmi les mauvaises notes. */
const BOUT = [
  { id: "bou_a", nom: "Alpha", secteur: "Informatique", categorie_id: "cat_hightech",
    note_moyenne: 4.2, nb_avis: 12, ordre: 1 },
  { id: "bou_b", nom: "Bêta", secteur: "Mode", categorie_id: "cat_mode",
    note_moyenne: null, nb_avis: 0, ordre: 2 },
  { id: "bou_c", nom: "Gamma", secteur: "Maison", categorie_id: "cat_maison",
    note_moyenne: 4.9, nb_avis: 40, ordre: 3 },
].map((b) => ({ ...b, icone: "magasin", couleur: "#0047D9", devise: "FCFA", indicatif: "229",
  actif: true, slogan: "Le slogan de " + b.nom, photos: [] }));

const PROD = [{ id: "prod_1", boutique_id: "bou_a", nom: "Ordinateur", code: "0001",
  reference: "", description: "Processeur : Intel Core i5\nRAM : 8 Go\nUn bel appareil.",
  prix: 300000, ancien_prix: 350000, categorie_id: "cat_hightech",
  sous_categorie_id: "sc_cat_hightech", stock: 5, sur_commande: false, disponible: true,
  en_avant: false, ordre_avant: 0, images: [], video: "",
  cree_le: "2026-09-01T08:00:00Z", modifie_le: "2026-09-01T08:00:00Z",
  note_moyenne: null, nb_avis: 0 }];

/* Une bannière de l'enseigne : c'est elle que « Nos boutiques
   partenaires » doit suivre sans rien d'intercalé. */
const SLIDES = [{ id: 1, boutique_id: null, portee: "enseigne", image: "BAN/banniere.jpg",
  titre: "La bannière", produit_id: null, ordre: 1, actif: true }];

const PANIER = [{ produitId: "prod_1", quantite: 1 }];
const COMMANDE = (etat) => ({ id: "cmd_x", numero: "BZ-000042", total: 300000, devise: "FCFA",
  etat, client: { nom: "Koffi", tel: "0197000000", indicatif: "229", adresse: "Cotonou" },
  boutiques: [{ id: "bou_a", nom: "Alpha", montant: 300000,
    lignes: [{ nom: "Ordinateur", prix: 300000, quantite: 1 }] }] });

async function ouvrir({ hash = "", panier = null, commandes = null, paiement = true,
                        largeur = 390 } = {}) {
  const ctx = await nav.newContext({ viewport: { width: largeur, height: 900 } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({
      url: "https://base-absente.invalid", cle: "cle-de-banc" }));
    localStorage.removeItem("impact-boutique");
    if (a.panier) localStorage.setItem("bizzoo-panier", JSON.stringify(a.panier));
    if (a.commandes) localStorage.setItem("bizzoo-commandes", JSON.stringify(a.commandes));
    localStorage.setItem("bizzoo-coordonnees", JSON.stringify({
      nom: "Koffi", tel: "0197000000", indicatif: "229", adresse: "Cotonou" }));
  }, { panier, commandes });
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json",
      body: JSON.stringify(x) });
    if (c.startsWith("categories")) return d(CATS);
    if (c.startsWith("boutiques")) return d(BOUT);
    if (c.startsWith("produits")) return d(PROD);
    if (c.startsWith("slides")) return d(SLIDES);
    if (c.startsWith("paiement")) return d(paiement
      ? [{ id: 1, actif: true, fournisseur: "feexpay", cle_publique: "", bac_a_sable: false }]
      : [{ id: 1, actif: false, fournisseur: "feexpay", cle_publique: "", bac_a_sable: true }]);
    if (c.startsWith("rpc/")) return d([]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA",
      indicatif: "229", whatsapp: "97000000" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200,
    contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/client/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  if (hash) {
    await page.evaluate((h) => { location.hash = h; }, hash);
    await page.waitForTimeout(1300);
  }
  return { page, ctx };
}

const barreVisible = (page) => page.evaluate(() => {
  const b = document.getElementById("tabbar");
  return !!b && getComputedStyle(b).display !== "none";
});
const action = (page) => page.evaluate(() => {
  const b = document.getElementById("barre-action");
  if (!b) return null;
  const btn = b.querySelector(".btn");
  return { texte: btn ? btn.textContent.trim() : "",
    orange: !!btn && btn.classList.contains("btn-orange"),
    fond: btn ? getComputedStyle(btn).backgroundColor : "" };
});

/* ------------------------------------------------------------------ */
titre("1. La barre du bas : les quatre onglets de la DA");
{
  const { page, ctx } = await ouvrir();
  const m = await page.evaluate(() => [...document.querySelectorAll("#tabbar [data-tab]")]
    .filter((a) => !a.hidden).map((a) => a.textContent.trim()));
  ok(m.join(",") === "Accueil,Catégories,Favoris,Compte",
    "Accueil, Catégories, Favoris, Compte — et rien d'autre (" + m.join(", ") + ")");
  ok(await barreVisible(page), "elle est là sur l'accueil");
  const actif = await page.evaluate(() =>
    (document.querySelector("#tabbar a.actif") || {}).textContent || "");
  ok(/Accueil/.test(actif), "et « Accueil » est allumé (" + actif.trim() + ")");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("2. Les écrans de parcours : pas de barre, une action en bas");
{
  const { page, ctx } = await ouvrir({ hash: "#/produit/prod_1" });
  ok(!(await barreVisible(page)), "la fiche produit n'a pas de barre d'onglets");
  const a = await action(page);
  ok(!!a && /Ajouter au panier/.test(a.texte), "elle a « Ajouter au panier » en bas");
  ok(!!a && a.orange && a.fond === "rgb(255, 138, 0)", "en ORANGE, comme la DA");

  /* L'ACTION NE SURVIT PAS À SON ÉCRAN. C'est le défaut qui se voit le
     moins en développant — on va toujours de l'avant — et le plus en
     vrai : « Ajouter au panier » resté collé sur l'accueil. */
  await page.evaluate(() => { location.hash = "#/"; });
  await page.waitForTimeout(900);
  ok((await action(page)) === null, "revenu à l'accueil, l'action du bas a disparu");
  ok(await barreVisible(page), "et la barre d'onglets est revenue");
  await ctx.close();
}
{
  const { page, ctx } = await ouvrir({ hash: "#/panier", panier: PANIER });
  ok(!(await barreVisible(page)), "le panier n'a pas de barre d'onglets");
  const a = await action(page);
  ok(!!a && /Passer la commande/.test(a.texte) && a.orange,
    "il a « Passer la commande », en orange (" + (a && a.texte) + ")");
  await ctx.close();
}
{
  const { page, ctx } = await ouvrir({ hash: "#/commande", panier: PANIER });
  const a = await action(page);
  /* LE PAIEMENT EST BLEU sur la DA : l'orange ne va qu'à ce qui ajoute
     au panier et au passage de commande. */
  ok(!!a && /^Payer/.test(a.texte) && !a.orange && a.fond === "rgb(0, 71, 217)",
    "le paiement a « Payer … », en BLEU (" + (a && a.texte) + ")");
  ok(!!a && /300\s000/.test(a.texte), "et le montant est dans le bouton");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("3. L'accueil dans l'ordre de la DA, et « Nos boutiques »");
{
  const { page, ctx } = await ouvrir();
  const m = await page.evaluate(() => {
    const vue = document.getElementById("vue");
    const ordre = (sel) => [...vue.children].findIndex((x) => x.matches(sel));
    const titreBoutiques = [...vue.children].findIndex((x) =>
      x.matches(".section-titre") && /Nos boutiques partenaires/.test(x.textContent));
    return {
      pilule: ordre(".recherche-pilule"), ronds: ordre(".cat-ronds"),
      slider: ordre(".slider"), titreBoutiques, tuiles: ordre(".bou-tuiles"),
      offre: ordre(".offre-jour"),
      titre: [...vue.querySelectorAll(".section-titre h2")].map((h) => h.textContent.trim()),
      noms: [...vue.querySelectorAll(".cat-rond-nom")].map((x) => x.textContent.trim()),
      lien: (document.querySelector(".recherche-pilule") || {}).getAttribute
        ? document.querySelector(".recherche-pilule").getAttribute("href") : "",
      toutVoir: [...vue.querySelectorAll(".section-lien")].map((a) => a.getAttribute("href")),
    };
  });
  ok(m.pilule === 0, "la recherche est en tête, comme la DA");
  ok(m.ronds > m.pilule, "les catégories en ronds viennent juste après");
  ok(m.lien === "#/recherche", "la barre de recherche mène à la recherche");
  ok(m.noms.join(",") === "Mode,Électronique,Maison,Beauté",
    "les ronds portent le nom court (" + m.noms.join(", ") + ")");
  ok(m.titre.includes("Nos boutiques partenaires"), "« Nos boutiques partenaires », le titre de la DA");
  /* LA DA N'INTERCALE RIEN entre la bannière et les boutiques : ce qui
     s'y glisse les repousse sous le premier écran. */
  ok(m.slider > m.ronds && m.titreBoutiques === m.slider + 1,
    "les boutiques suivent la bannière, sans rien entre les deux");
  ok(m.offre > m.tuiles, "l'offre du jour vient ensuite, sous les boutiques");
  ok(m.toutVoir.includes("#/boutiques"), "et « Tout voir » ouvre la liste des boutiques");
  await ctx.close();
}
{
  const { page, ctx } = await ouvrir({ hash: "#/boutiques" });
  const toutes = await page.evaluate(() =>
    [...document.querySelectorAll(".bou-ligne-nom")].map((x) => x.textContent));
  ok(toutes.join(",") === "Alpha,Bêta,Gamma", "« Toutes » : l'ordre de l'enseigne (" +
    toutes.join(", ") + ")");
  const sansAvis = await page.evaluate(() =>
    [...document.querySelectorAll(".bou-ligne")].find((l) => /Bêta/.test(l.textContent))
      .textContent);
  ok(/Pas encore d'avis/.test(sansAvis),
    "une boutique sans avis le dit, plutôt qu'afficher un zéro");
  await page.click('#bou-filtres [data-filtre="top"]');
  await page.waitForTimeout(300);
  const top = await page.evaluate(() =>
    [...document.querySelectorAll(".bou-ligne-nom")].map((x) => x.textContent));
  /* LE CONSTAT QUI COMPTE : « Bêta » n'a AUCUN avis. La ranger après
     les autres la ferait passer pour la plus mal notée. */
  ok(top.join(",") === "Gamma,Alpha",
    "« Top » : la mieux notée d'abord, et les sans-avis écartées (" + top.join(", ") + ")");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("4. La fiche boutique : trois onglets, et des atouts vrais");
{
  const { page, ctx } = await ouvrir({ hash: "#/boutique/bou_a" });
  ok(!(await barreVisible(page)), "pas de barre d'onglets, comme la DA");
  const m = await page.evaluate(() => ({
    onglets: [...document.querySelectorAll(".bou-onglet")].map((o) => o.textContent.trim()),
    atouts: [...document.querySelectorAll(".bou-atout")].map((a) => a.textContent.trim()),
    suivre: (document.getElementById("bou-suivre") || {}).textContent || "",
    premier: (() => {
      const x = [...document.getElementById("bou-contenu").children]
        .find((e) => !e.matches(".note-hors-ligne"));
      return x ? x.className : "";
    })(),
  }));
  ok(m.onglets.join(",") === "Produits,Avis,À propos", "Produits, Avis, À propos");
  /* Sous les onglets, la DA pose les vignettes. Une bannière devant
     les repousserait sous le premier écran. */
  ok(/\bbou-vignettes\b/.test(m.premier),
    "sous « Produits », les vignettes d'abord (" + m.premier + ")");
  ok(/Suivre/.test(m.suivre), "et le bouton « Suivre »");
  ok(m.atouts.includes("Paiement sécurisé"), "paiement ouvert : « Paiement sécurisé » s'affiche");
  /* LES ATOUTS DE LA MAQUETTE NE SONT PAS RECOPIÉS : « Produits certifiés »
     sur toutes les fiches serait une promesse que personne n'a vérifiée. */
  ok(!m.atouts.some((a) => /certifi/i.test(a)), "et aucun « Produits certifiés » inventé");
  await page.click('.bou-onglet[data-onglet="apropos"]');
  await page.waitForTimeout(400);
  const apropos = await page.evaluate(() =>
    document.getElementById("bou-contenu").textContent);
  ok(/Nous contacter/.test(apropos), "« À propos » montre ses coordonnées");
  await ctx.close();
}
{
  const { page, ctx } = await ouvrir({ hash: "#/boutique/bou_a", paiement: false });
  const atouts = await page.evaluate(() =>
    [...document.querySelectorAll(".bou-atout")].map((a) => a.textContent.trim()));
  ok(!atouts.includes("Paiement sécurisé"),
    "paiement fermé : « Paiement sécurisé » ne s'affiche PAS (" + atouts.join(", ") + ")");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("5. Le panier : aucun frais de livraison inventé");
{
  const { page, ctx } = await ouvrir({ hash: "#/panier", panier: PANIER });
  const m = await page.evaluate(() => {
    const recap = document.querySelector(".pa-recap");
    const livraison = [...recap.querySelectorAll(".pa-recap-ligne")]
      .find((l) => /Livraison/.test(l.textContent));
    return { titre: (document.querySelector(".topbar h1") || {}).textContent || "",
      livraison: livraison ? livraison.textContent : "",
      vider: !!document.getElementById("pa-vider") };
  });
  ok(/Mon panier \(1\)/.test(m.titre), "« Mon panier (1) », le titre de la DA (" + m.titre + ")");
  ok(m.vider, "« Supprimer tout » est là");
  /* La maquette écrit « 5 000 FCFA ». Ici la livraison se convient avec
     la boutique : un montant serait un chiffre que personne n'a fixé. */
  ok(/À convenir/.test(m.livraison) && !/\d/.test(m.livraison),
    "la livraison est « À convenir », sans montant (" + m.livraison.trim() + ")");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("6. Le paiement : les vrais opérateurs");
{
  const { page, ctx } = await ouvrir({ hash: "#/commande", panier: PANIER });
  const m = await page.evaluate(() => ({
    titre: (document.querySelector(".topbar h1") || {}).textContent || "",
    methodes: [...document.querySelectorAll("#co-operateurs .pay-methode strong")]
      .map((x) => x.textContent.trim()),
    texte: document.getElementById("vue").textContent,
  }));
  ok(m.titre === "Paiement", "l'écran s'appelle « Paiement », comme la DA");
  ok(m.methodes.join(",") === "MTN,Moov,Celtiis",
    "MTN, Moov, Celtiis — les opérateurs du Bénin (" + m.methodes.join(", ") + ")");
  ok(!/Orange Money/i.test(m.texte), "pas d'« Orange Money », qui n'existe pas ici");
  ok(!/Carte bancaire/i.test(m.texte), "ni de « Carte bancaire », que FeexPay n'ouvre pas ici");

  /* LE CHOIX SE LIT : la ligne pressée devient la seule active, et le
     lecteur d'écran l'entend (« aria-checked »). */
  await page.click('#co-operateurs [data-reseau="MOOV"]');
  const choix = await page.evaluate(() =>
    [...document.querySelectorAll("#co-operateurs .pay-methode")]
      .map((l) => l.dataset.reseau + ":" + l.classList.contains("active") + ":" +
        l.getAttribute("aria-checked")));
  ok(choix.join(",") === "MTN:false:false,MOOV:true:true,CELTIIS:false:false",
    "Moov pressé : lui seul est choisi (" + choix.join(", ") + ")");

  /* L'adresse connue se résume, et « Modifier » rouvre le formulaire —
     celui que la commande lit. */
  const avant = await page.evaluate(() => ({
    resume: !!document.getElementById("co-resume") && !document.getElementById("co-resume").hidden,
    formulaire: !document.getElementById("co-formulaire").hidden }));
  ok(avant.resume && !avant.formulaire, "l'adresse déjà connue est résumée, comme la DA");
  await page.click("#co-modifier");
  const apres = await page.evaluate(() => ({
    formulaire: !document.getElementById("co-formulaire").hidden,
    nom: document.getElementById("co-nom").value }));
  ok(apres.formulaire && apres.nom === "Koffi", "« Modifier » rouvre le formulaire, déjà rempli");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("7. La confirmation : seulement quand c'est vrai");
{
  const { page, ctx } = await ouvrir({ hash: "#/commande/cmd_x",
    commandes: [COMMANDE("payee")] });
  const m = await page.evaluate(() => {
    const h = document.querySelector(".re-heros");
    return { heros: !!h, texte: h ? h.textContent : "",
      boutons: h ? [...h.querySelectorAll(".btn")].map((b) => b.textContent.trim()) : [] };
  });
  ok(m.heros && /Commande confirmée/.test(m.texte), "payée : « Commande confirmée ! »");
  ok(m.boutons.join(",") === "Voir mes commandes,Retour à l'accueil",
    "avec les deux boutons de la DA (" + m.boutons.join(", ") + ")");
  /* La maquette promet un e-mail. BIZZOO n'en envoie pas. */
  ok(!/e-mail|email|courriel/i.test(m.texte), "et aucune promesse d'e-mail");
  ok(!(await barreVisible(page)), "pas de barre d'onglets, comme la DA");
  /* Une seule boutique : le singulier, et le numéro qui se dicte par
     groupes de deux — celui qu'on va décrocher. */
  const confirme = await page.evaluate(() =>
    (document.querySelector(".pa-confirme") || {}).textContent || "");
  ok(/La boutique a reçu votre commande dans son compte\. Elle vous rappelle au \+229 01 97 00 00 00 /
    .test(confirme), "une boutique : « Elle vous rappelle au +229 01 97 00 00 00 »");
  await ctx.close();
}
{
  const { page, ctx } = await ouvrir({ hash: "#/commande/cmd_x",
    commandes: [COMMANDE("a_payer")] });
  const heros = await page.evaluate(() => !!document.querySelector(".re-heros"));
  /* LE CONSTAT QUI COMPTE LE PLUS. Annoncer « confirmée » avant que la
     base ait constaté le versement, c'est promettre une commande que
     les boutiques n'ont peut-être jamais reçue. */
  ok(!heros, "à payer : AUCUNE coche « confirmée » tant que la base n'a rien constaté");
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec.\n"
  : "\nLes huit écrans de la DA tiennent ✔\n");
process.exit(echecs ? 1 : 0);
