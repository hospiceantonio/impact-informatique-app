/* =========================================================
   La publicité s'enchaîne : une vidéo finit, la suivante part
   =========================================================
   TROIS VRAIES VIDÉOS d'une seconde, servies par le serveur
   local. Une doublure de lecteur ne prouverait rien : c'est
   l'événement « ended » du vrai <video> qui déclenche tout.
   ========================================================= */
import { readFileSync } from "node:fs";

/* Playwright n'est pas une dépendance du projet : les deux applications
   n'en ont aucune. Le chemin se donne par PLAYWRIGHT. */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-publicite.mjs");
  process.exit(2);
}

const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";

/* LES VIDÉOS D'ESSAI, en WebM et non en MP4. Un Chromium bâti à partir
   des sources n'embarque pas H.264, qui est un codec propriétaire : le
   MP4 du gérant s'y refuse avec « l'élément n'a aucune source », et
   l'essai croirait éprouver l'enchaînement alors qu'aucune vidéo ne
   peut commencer. Ce qu'on éprouve ici — l'événement « ended » d'un
   <video> — ne dépend pas du format. Trois fichiers d'une seconde
   suffisent ; pour les fabriquer :

     ffmpeg -f lavfi -i "color=c=blue:s=320x200:d=1" -c:v libvpx pub1.webm */
const VIDEOS = process.env.VIDEOS || "/tmp/claude-0/videos";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch({
  ...(EXE ? { executablePath: EXE } : {}),
  /* Sans cela, le navigateur refuse le « play() » de l'essai lui-même
     — pas celui de l'application, qui part d'un vrai geste. */
  args: ["--autoplay-policy=no-user-gesture-required"] });

/* UN ACCUEIL DE VRAIE TAILLE — huit catégories et six boutiques, comme
   en service. Ce n'est pas du décor : le constat « la page n'a pas
   sauté » n'a de sens que si la publicité est SOUS le pli. Avec une
   seule catégorie et une seule boutique, l'accueil tenait dans la
   fenêtre, « scrollTo » ne faisait rien, et le sabotage passait
   inaperçu. La grille des boutiques étant passée à trois colonnes,
   l'accueil a encore raccourci — d'où ce décor, qui le rallonge.
   Depuis la 3.50.0, la publicité passe AVANT les boutiques, juste sous
   le slider et les catégories : c'est désormais la bannière du haut —
   il y en a une en service — qui la pousse sous le pli. */
const CAT = Array.from({ length: 8 }, (_, i) => ({
  id: i === 0 ? "cat_h" : "cat_" + i, nom: i === 0 ? "High-Tech" : "Rayon " + i,
  icone: "portable", couleur: "#0B5CF5", en_avant: true, ordre: i + 1,
  sous_categories: i === 0 ? [{ id:"sc_o", nom:"Ordinateurs", ordre:1 }] : [],
}));
const BOU = Array.from({ length: 6 }, (_, i) => ({
  id: i === 0 ? "bou_tech" : "bou_" + i, nom: i === 0 ? "IMPACT" : "BOUTIQUE " + i,
  secteur: "Informatique", categorie_id: "cat_h", icone: "portable",
  couleur: "#0B5CF5", devise: "FCFA", indicatif: "229", actif: true, ordre: i + 1,
}));
const PR = [{ id:"prod_hp", boutique_id:"bou_tech", nom:"Ordinateur HP", code:"0001",
  reference:"", description:"d", prix:385000, ancien_prix:null, categorie_id:"cat_h",
  sous_categorie_id:"sc_o", stock:5, sur_commande:false, disponible:true,
  en_avant:false, ordre_avant:0, images:[], video:"",
  cree_le:"2026-09-01T08:00:00Z", modifie_le:"2026-09-01T08:00:00Z" }];

/* La rangée de publicité : « portee: publicite ». Le troisième écran
   est une AFFICHE et non une vidéo — c'est le cas qui dit où la
   chaîne doit s'arrêter. */
function slides(avecImage) {
  const l = [
    /* La bannière de l'enseigne, en tête de l'accueil, comme en service. */
    { id:"s0", portee:"enseigne", actif:true, ordre:1, titre:"Bannière",
      video:"", image:"banniere.png", produit_id:null },
    { id:"s1", portee:"publicite", actif:true, ordre:1, titre:"Pub une",
      video:"pub1.webm", image:"", produit_id:null },
    { id:"s2", portee:"publicite", actif:true, ordre:2, titre:"Pub deux",
      video:"pub2.webm", image:"", produit_id:null },
  ];
  l.push(avecImage
    ? { id:"s3", portee:"publicite", actif:true, ordre:3, titre:"Affiche",
        video:"", image:"affiche.png", produit_id:null }
    : { id:"s3", portee:"publicite", actif:true, ordre:3, titre:"Pub trois",
        video:"pub3.webm", image:"", produit_id:null });
  return l;
}

async function ouvrir(avecImage, hauteur) {
  const ctx = await nav.newContext({ viewport:{ width:390, height:hauteur || 1800 } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));
  await page.addInitScript(() => {
    localStorage.setItem("impact-config", JSON.stringify({
      url:"https://base-absente.invalid", cle:"cle-de-banc" }));
    localStorage.removeItem("impact-boutique");
  });
  /* LE STOCKAGE, SERVI AVEC LES REQUÊTES DE PLAGE. Chromium demande un
     média par tranches (« Range: bytes=0- ») et attend un 206 avec la
     tranche exacte. Une doublure qui répond 200 avec tout le fichier
     lui fait dire « l'élément n'a aucune source » — et l'essai croirait
     éprouver l'enchaînement alors qu'aucune vidéo ne peut commencer. */
  await page.route("**/storage/v1/object/public/produits/**", (route) => {
    const nom = route.request().url().split("/").pop();
    const png = !/\.webm$/.test(nom);
    const corps = png
      ? Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk" +
                    "+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==", "base64")
      : readFileSync(VIDEOS + "/" + nom);
    const type = png ? "image/png" : "video/webm";
    const plage = route.request().headers()["range"];
    if (!plage) {
      return route.fulfill({ status: 200, body: corps,
        headers: { "Content-Type": type, "Accept-Ranges": "bytes",
          "Content-Length": String(corps.length) } });
    }
    const m = /bytes=(\d*)-(\d*)/.exec(plage) || [];
    const debut = m[1] ? parseInt(m[1], 10) : 0;
    const fin = m[2] ? parseInt(m[2], 10) : corps.length - 1;
    const tranche = corps.subarray(debut, fin + 1);
    return route.fulfill({ status: 206, body: tranche,
      headers: { "Content-Type": type, "Accept-Ranges": "bytes",
        "Content-Length": String(tranche.length),
        "Content-Range": "bytes " + debut + "-" + fin + "/" + corps.length } });
  });

  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//,"");
    const d = (x) => route.fulfill({ status:200, contentType:"application/json", body:JSON.stringify(x) });
    if (c === "rpc/produits_populaires") return d([]);
    if (c.startsWith("slides")) return d(slides(avecImage));
    if (c.startsWith("categories")) return d(CAT);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("produits")) return d(PR);
    if (c.startsWith("boutique")) return d([{id:1,nom:"BIZZOO",devise:"FCFA",indicatif:"229"}]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html", { waitUntil:"domcontentloaded" });
  await page.waitForTimeout(2300);
  return { page, ctx };
}

/* Quelle vidéo joue, et où en est la rangée. */
const etat = (page) => page.evaluate(() => {
  const r = document.querySelector(".pub-rangee");
  const v = [...document.querySelectorAll("video.pub-media")];
  return {
    nb: v.length,
    joue: v.map((x) => !x.paused).indexOf(true),
    finies: v.map((x) => x.ended),
    defile: r ? Math.round(r.scrollLeft) : -1,
  };
});

titre("Le décor : trois écrans de publicité");
{
  const { page, ctx } = await ouvrir(false);
  const e = await etat(page);
  ok(e.nb === 3, "trois vidéos dans la rangée (" + e.nb + ")");
  /* RIEN NE DÉMARRE TOUT SEUL : c'est la règle d'avant, et elle tient. */
  ok(e.joue === -1, "et aucune ne joue avant qu'on y touche");
  ok(e.defile >= 0, "la rangée est à son point de départ (" + e.defile + " px)");
  await ctx.close();
}

titre("On lance la première : la chaîne suit toute la rangée");
{
  const { page, ctx } = await ouvrir(false);
  /* ON ENREGISTRE LA SUITE DES LECTURES au lieu de sonder à intervalles
     devinés. Un essai qui regarde « qui joue » à 3 secondes constate le
     hasard de ses propres délais : ici on relève l'ORDRE, qui est ce
     que l'enchaînement promet. */
  await page.evaluate(() => {
    window.__suite = [];
    [...document.querySelectorAll("video.pub-media")].forEach((v, i) => {
      v.addEventListener("play", () => window.__suite.push(i));
    });
  });
  await page.evaluate(() => document.querySelectorAll("video.pub-media")[0].play());
  await page.waitForTimeout(6000);

  const suite = await page.evaluate(() => window.__suite);
  ok(suite.join(",") === "0,1,2",
    "les trois se sont enchaînées dans l'ordre (" + suite.join(" → ") + ")");
  const e = await etat(page);
  ok(e.finies.every(Boolean), "et toutes sont allées jusqu'au bout");
  ok(e.defile > 400, "la rangée a suivi (" + e.defile + " px)");
  await ctx.close();
}

titre("Jamais deux vidéos ensemble");
{
  const { page, ctx } = await ouvrir(false);
  await page.evaluate(() => document.querySelectorAll("video.pub-media")[0].play());
  await page.waitForTimeout(300);
  /* Le client lance la troisième à la main pendant que la première
     tourne : la première doit s'arrêter. Deux vidéos ensemble, c'est
     le double du débit et un téléphone qui chauffe. */
  await page.evaluate(() => document.querySelectorAll("video.pub-media")[2].play());
  await page.waitForTimeout(400);
  const combien = await page.evaluate(() =>
    [...document.querySelectorAll("video.pub-media")].filter((v) => !v.paused).length);
  ok(combien === 1, "une seule joue à la fois (" + combien + ")");
  await ctx.close();
}

titre("Au bout de la rangée, la chaîne s'arrête — elle ne boucle pas");
{
  const { page, ctx } = await ouvrir(false);
  await page.evaluate(() => document.querySelectorAll("video.pub-media")[2].play());
  await page.waitForTimeout(2600);
  const e = await etat(page);
  ok(e.finies[2] === true, "la dernière est finie");
  ok(e.joue === -1, "et rien ne repart au début (" + e.joue + ")");
  await ctx.close();
}

titre("Une affiche arrête la chaîne : on ne la saute pas");
{
  const { page, ctx } = await ouvrir(true);
  const nb = await page.evaluate(() => document.querySelectorAll("video.pub-media").length);
  ok(nb === 2, "deux vidéos et une affiche (" + nb + " vidéos)");
  await page.evaluate(() => document.querySelectorAll("video.pub-media")[1].play());
  await page.waitForTimeout(2600);
  const e = await etat(page);
  ok(e.finies[1] === true, "la deuxième vidéo est finie");
  ok(e.joue === -1, "aucune vidéo ne joue : on s'est arrêté sur l'affiche");
  ok(e.defile > 100, "mais la rangée a bien avancé jusqu'à elle (" + e.defile + " px)");
  await ctx.close();
}

titre("La page n'a pas sauté sous les yeux du client");
{
  /* UNE FENÊTRE COURTE, ET C'EST TOUT LE SUJET. Dans une fenêtre de
     1 800 px la page tient en entier : elle ne peut pas défiler, et le
     constat resterait vert même avec « scrollIntoView », qui fait
     pourtant sauter tout l'accueil. Éprouvé sur 640 px — la hauteur
     utile d'un téléphone —, il mord. */
  const { page, ctx } = await ouvrir(false, 640);
  /* On descend jusqu'à la rangée : c'est là que le client est quand il
     lance une vidéo. */
  await page.evaluate(() => {
    const r = document.querySelector(".pub-rangee");
    /* La rangée est amenée EN BAS de l'écran, pas en haut. C'est ce
       qui donne sa morsure au constat : « scrollIntoView » veut poser
       la carte en HAUT de la fenêtre, donc remonter toute la page. Vue
       en haut, elle y est déjà, et le sabotage passerait inaperçu. */
    if (r) window.scrollTo(0, r.getBoundingClientRect().top + window.scrollY -
                              (window.innerHeight - 160));
  });
  await page.waitForTimeout(500);
  const avant = await page.evaluate(() => Math.round(window.scrollY));
  ok(avant > 0, "la page est bien descendue jusqu'à la publicité (" + avant + " px)");

  await page.evaluate(() => document.querySelectorAll("video.pub-media")[0].play());
  await page.waitForTimeout(2600);
  const apres = await page.evaluate(() => Math.round(window.scrollY));
  /* « scrollIntoView » ferait sauter tout l'accueil pour montrer une
     publicité : le défilement doit porter sur la RANGÉE seule. */
  ok(Math.abs(apres - avant) <= 2,
    "et elle est restée où elle était (" + avant + " → " + apres + ")");
  const defile = await page.evaluate(() =>
    Math.round(document.querySelector(".pub-rangee").scrollLeft));
  ok(defile > 100, "pendant que la rangée, elle, a avancé (" + defile + " px)");
  await ctx.close();
}

await nav.close();
console.log("\n" + (echecs ? "  " + echecs + " ÉCHEC(S)" : "  Tout passe."));
process.exit(echecs ? 1 : 0);
