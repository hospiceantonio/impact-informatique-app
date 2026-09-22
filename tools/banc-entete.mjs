/* La fiche d'une boutique : son nom en entier, son slogan dessous.

   CE BANC A CHANGÉ D'OBJET AVEC LA DA CORRIGÉE, pas de règle. Il
   gardait l'en-tête COLLANT de la boutique, où le nom se coupait en
   « IMP… » faute de place : il exigeait donc une seule ligne, et un
   en-tête court. Le nom et le slogan sont descendus dans la fiche, qui
   défile avec la page : la hauteur ne pèse plus sur l'écran entier, et
   un nom long peut prendre deux lignes plutôt que perdre des lettres.
   Ce qui ne change pas, et que chaque constat garde : le nom se lit EN
   ENTIER, le slogan est DESSOUS, le logo À GAUCHE, et l'en-tête qui
   reste collé en haut ne mange pas l'écran. */
/* Playwright n'est pas une dépendance du projet : le chemin se donne
   par PLAYWRIGHT, le navigateur par CHROMIUM, l'adresse par BANC_URL. */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-entete.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

/* LE CAS RÉEL, relevé sur la capture du gérant : un nom long et un
   slogan long. C'est là que l'ancien en-tête donnait « IMP… ». */
const NOM = "IMPACT INFORMATIQUE";
const SLOGAN = "Nous sommes imbattables en prix";

const BOU = [{ id:"bou_tech", nom:NOM, secteur:"Informatique", slogan:SLOGAN,
  categorie_id:"cat_h", icone:"portable", couleur:"#0B5CF5", devise:"FCFA",
  indicatif:"229", actif:true, ordre:1 }];
const CAT = [{ id:"cat_h", nom:"High-Tech", icone:"portable", couleur:"#0B5CF5",
  en_avant:true, ordre:1, sous_categories:[{id:"sc_o",nom:"Ordinateurs",ordre:1}] }];
const PR = [{ id:"prod_hp", boutique_id:"bou_tech", nom:"Ordinateur HP", code:"0001",
  reference:"", description:"d", prix:385000, ancien_prix:null, categorie_id:"cat_h",
  sous_categorie_id:"sc_o", stock:5, sur_commande:false, disponible:true,
  en_avant:false, ordre_avant:0, images:[], video:"",
  cree_le:"2026-09-01T08:00:00Z", modifie_le:"2026-09-01T08:00:00Z" }];

async function ouvrir(largeur, nom) {
  const ctx = await nav.newContext({ viewport:{ width:largeur, height:1400 } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));
  await page.addInitScript(() => {
    localStorage.setItem("impact-config", JSON.stringify({ url:"https://base-absente.invalid", cle:"k" }));
    localStorage.removeItem("impact-boutique");
  });
  await page.route("**/rest/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/rest\/v1\//,"");
    const d = (x) => r.fulfill({status:200,contentType:"application/json",body:JSON.stringify(x)});
    if (c === "rpc/produits_populaires") return d([]);
    if (c.startsWith("categories")) return d(CAT);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("produits")) return d(PR);
    if (c.startsWith("boutique")) return d([{id:1,nom:"BIZZOO",devise:"FCFA",indicatif:"229"}]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html", { waitUntil:"domcontentloaded" });
  await page.waitForTimeout(1600);
  await page.evaluate(() => { location.hash = "#/boutique/bou_tech"; });
  await page.waitForTimeout(1600);
  if (nom) await page.screenshot({ path:(process.env.CAPTURES || ".")+"/"+nom+".png", fullPage:false });
  return { page, ctx };
}

const mesure = (page) => page.evaluate(() => {
  const h = document.querySelector(".bou-fiche-nom");
  const s = document.querySelector(".bou-fiche-slogan");
  const v = document.querySelector(".bou-fiche .bou-logo");
  const bar = document.querySelector(".topbar");
  /* « line-height » vaut souvent « normal », que parseFloat rend en
     NaN. On compare donc la hauteur à la taille de police : au-delà
     d'une fois et demie, le texte s'est replié. */
  const ligne = (el) => {
    if (!el) return 0;
    const st = getComputedStyle(el);
    const h = el.getBoundingClientRect().height;
    const unite = parseFloat(st.lineHeight) ||
                  parseFloat(st.fontSize) * 1.35;
    return Math.max(1, Math.round(h / unite));
  };
  return {
    nom: h ? h.textContent : "",
    /* Coupé, c'est perdre des lettres : dans la largeur (points de
       suspension), ou dans la hauteur — mais SEULEMENT si l'élément
       masque ce qui dépasse. Sans cela, on compterait comme coupées
       les lettres de Poppins qui débordent de 2 px une ligne serrée,
       et qui restent parfaitement visibles : le banc l'a fait. */
    nomCoupe: h ? h.scrollWidth > h.clientWidth + 1 ||
      (getComputedStyle(h).overflowY !== "visible" && h.scrollHeight > h.clientHeight + 1) : false,
    sloganCoupeLargeur: s ? s.scrollWidth > s.clientWidth + 1 : false,
    lignesNom: ligne(h),
    slogan: s ? s.textContent : "",
    lignesSlogan: ligne(s),
    hauteur: bar ? Math.round(bar.getBoundingClientRect().height) : 0,
    logoX: v ? Math.round(v.getBoundingClientRect().left) : -1,
    nomX: h ? Math.round(h.getBoundingClientRect().left) : -1,
    nomY: h ? Math.round(h.getBoundingClientRect().top) : -1,
    sloganY: s ? Math.round(s.getBoundingClientRect().top) : -1,
    largeurNom: h ? Math.round(h.getBoundingClientRect().width) : 0,
  };
});

for (const [l, quoi] of [[360,"un petit téléphone (360)"],[390,"un téléphone courant (390)"]]) {
  titre("L'enseigne se lit en entier — sur " + quoi);
  const { page, ctx } = await ouvrir(l, l === 390 ? "entete-tel" : null);
  const m = await mesure(page);
  ok(m.nom === NOM, "le nom est celui de la boutique (" + m.nom + ")");
  ok(!m.nomCoupe, "et il n'est PAS coupé" + (m.nomCoupe ? " — « " + m.nom + " »" : ""));
  ok(m.lignesNom <= 2, "sur deux lignes au plus (" + m.lignesNom + ")");
  ok(m.largeurNom > 200,
    "il dispose de la largeur qu'il faut (" + m.largeurNom + " px, contre ~120 avant)");
  ok(m.lignesSlogan >= 1 && m.lignesSlogan <= 3, "le slogan tient en trois lignes au plus (" +
    m.lignesSlogan + ")");
  ok(!m.sloganCoupeLargeur, "sans rien perdre en largeur");
  ok(m.sloganY > m.nomY, "et il est EN DESSOUS du nom");
  ok(m.logoX < m.nomX, "le logo est à gauche du nom");
  ok(m.logoX < 60, "au début de la ligne (" + m.logoX + " px du bord)");
  /* L'en-tête qui reste collé en haut ne porte plus que le retour, la
     cloche et le panier : il doit rester court. */
  ok(m.hauteur < 140, "et l'en-tête ne mange pas l'écran (" + m.hauteur + " px)");
  await ctx.close();
}

titre("Un slogan très long ne déborde toujours pas");
{
  BOU[0].slogan = "Nous sommes imbattables en prix sur tout le matériel " +
    "informatique, les consommables et les accessoires, à Cotonou comme ailleurs";
  const { page, ctx } = await ouvrir(390, "entete-long");
  const m = await mesure(page);
  ok(m.lignesSlogan <= 3, "il s'arrête à trois lignes (" + m.lignesSlogan + ")");
  ok(m.hauteur < 140, "et l'en-tête garde sa hauteur (" + m.hauteur + " px)");
  const deborde = await page.evaluate(() =>
    document.documentElement.scrollWidth > document.documentElement.clientWidth + 1);
  ok(!deborde, "rien ne déborde en largeur");
  await ctx.close();
}

titre("L'accueil de BIZZOO n'a pas bougé");
{
  BOU[0].slogan = SLOGAN;
  const ctx = await nav.newContext({ viewport:{ width:390, height:1400 } });
  const page = await ctx.newPage();
  await page.addInitScript(() => {
    localStorage.setItem("impact-config", JSON.stringify({ url:"https://base-absente.invalid", cle:"k" }));
    localStorage.removeItem("impact-boutique");
  });
  await page.route("**/rest/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/rest\/v1\//,"");
    const d = (x) => r.fulfill({status:200,contentType:"application/json",body:JSON.stringify(x)});
    if (c === "rpc/produits_populaires") return d([]);
    if (c.startsWith("categories")) return d(CAT);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("produits")) return d(PR);
    if (c.startsWith("boutique")) return d([{id:1,nom:"BIZZOO",devise:"FCFA",indicatif:"229"}]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html", { waitUntil:"domcontentloaded" });
  await page.waitForTimeout(1800);
  const t = await page.evaluate(() => ({
    logo: !!document.querySelector(".topbar .logo-mot"),
    enseigne: !!document.querySelector(".bou-fiche"),
  }));
  ok(t.logo, "le logo BIZZOO est toujours là");
  ok(!t.enseigne, "et la fiche de boutique ne s'y invite pas");
  await ctx.close();
}

await nav.close();
console.log("\n" + (echecs ? "  " + echecs + " ÉCHEC(S)" : "  Tout passe."));
process.exit(echecs ? 1 : 0);
