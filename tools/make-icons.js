/* =========================================================
   Fabrique les icônes des applications BIZZOO Market (4.3.0)
   à partir du LOGO B officiel (tools/bizzoo-logo-b.png, la planche
   « BIZZOO Market — Logo B seul » de la direction artistique) : la
   tuile turquoise, le B blanc, son orbite turquoise et la vague pétrole.

   Le logo est une tuile complète, fond compris : on ne recompose plus
   un fond derrière un monogramme. La recette :

     1. DÉTOURER : le blanc autour de la tuile, atteint depuis les quatre
        coins (le B, blanc lui aussi, n'y est pas relié), devient
        transparent ; on ronge le bord de quelques pixels pour ne garder
        aucun pixel mêlé de blanc ;
     2. PROLONGER le fond de la tuile au-delà de ses bords et dans ses
        coins arrondis, en douceur (on moyenne les couleurs du bord, de
        plus en plus loin) : chaque forme peut alors réduire le logo pour
        le faire tenir dans le masque du téléphone sans laisser voir de
        bord blanc ni de couture ;
     3. CADRER chaque forme à l'échelle que son masque permet.

   Les formes :
     - tuile    (PWA 192/512, Android d'avant la version 8) : coins
                arrondis compris dans l'image ;
     - plein    (iPhone, « apple-touch-icon ») : carré plein, que
                l'iPhone arrondit lui-même ;
     - maskable (PWA installée sur Android) : le logo tient dans le
                disque de 80 % que tout masque respecte ;
     - rond     (Android, lanceurs à icônes rondes) ;
     - adaptative (Android 8 et plus) : deux calques, le fond prolongé et
                le logo, réduit pour que l'orbite tienne dans le disque
                de 72 dp sur 108 que les lanceurs laissent voir.

   Les PASTILLES, comme la planche des icônes de la direction
   artistique : BIZZOO (le client) porte un chariot blanc sur un disque
   turquoise ; BIZZOO Admin et BIZZOO Personnel, une roue dentée pétrole
   sur un disque blanc. Elles sont en bas à droite, sans toucher au B :
   sur un même téléphone, on distingue les applications d'un coup d'œil.
   Le LOGO (icons/logo-bizzoo-b.png), lui, est la tuile seule, sans
   pastille : la marque, pas l'icône d'une application.

   La petite icône de la barre de notifications
   (android/app/src/main/res/drawable/ic_notification.xml) n'est plus
   produite ici : c'est la silhouette du B et de son orbite, les mêmes
   formes que dans le nouveau logo, tracée en 4.0.0 et gardée telle
   quelle (sur la tuile turquoise, l'orbite et le fond se confondraient).

   Dépendance : Chromium, piloté par Playwright.
   Usage : node tools/make-icons.js
           (PLAYWRIGHT=<chemin de playwright-core> et CHROMIUM=<exécutable>)
   ========================================================= */
const fs = require("fs");
const path = require("path");

function chargerChromium() {
  const essais = [process.env.PLAYWRIGHT, "playwright", "playwright-core",
    "/opt/node22/lib/node_modules/playwright"].filter(Boolean);
  for (const nom of essais) {
    try {
      const mod = require(nom);
      const c = mod.chromium || (mod.default && mod.default.chromium);
      if (c) return c;
    } catch (_) { /* on essaie le suivant */ }
  }
  console.error("Playwright est nécessaire : npm i -g playwright (ou PLAYWRIGHT=<chemin>)");
  process.exit(1);
}

const RACINE = path.join(__dirname, "..");
const SOURCE = path.join(__dirname, "bizzoo-logo-b.png");

/* La taille de la tuile, en fraction du côté de l'image, pour chaque
   forme. L'orbite va presque d'un bord à l'autre de la tuile : là où le
   masque est un disque, la tuile est réduite et son fond prolongé. */
const ECHELLE = { tuile: 1, plein: 1, maskable: 0.80, rond: 0.92, "premier-plan": 0.64, fond: 0.64, logo: 1 };
/* Le rayon des coins de la tuile (forme « tuile »), en fraction du côté. */
const RAYON_TUILE = 0.225;
/* Les pixels rongés au bord de la tuile détourée (sur l'image source). */
const RONGER = 3;

/* (4.3.0) DES NOMS NEUFS, ENCORE : l'hébergement laisse un navigateur
   garder une image une semaine ; sous les noms de la 4.2.0, il montrerait
   l'ancien logo, gardé en mémoire. Sous un nom neuf, aucun cache ne peut
   le servir. Les ANCIENS NOMS (ceux de la 4.2.0 et ceux d'avant) sont
   écrits aussi, avec le nouveau logo : une adresse déjà partie (un
   e-mail, une icône d'écran d'accueil) le montre aussi. */
const CIBLES_PWA = [
  ["icone-b-192.png", 192, "tuile"],
  ["icone-b-512.png", 512, "tuile"],
  ["icone-b-maskable-512.png", 512, "maskable"],
  ["apple-touch-icon-b.png", 180, "plein"],
];
const ANCIENS_NOMS = {
  "icone-b-192.png": ["icone-market-192.png", "icon-192.png"],
  "icone-b-512.png": ["icone-market-512.png", "icon-512.png"],
  "icone-b-maskable-512.png": ["icone-market-maskable-512.png", "icon-maskable-512.png"],
  "apple-touch-icon-b.png": ["apple-touch-icon-market.png", "apple-touch-icon.png"],
  "logo-bizzoo-b.png": ["logo-bizzoo-market.png", "logo-bizzoo.png"],
};
const DENSITES = [
  ["mipmap-mdpi", 48, 108],
  ["mipmap-hdpi", 72, 162],
  ["mipmap-xhdpi", 96, 216],
  ["mipmap-xxhdpi", 144, 324],
  ["mipmap-xxxhdpi", 192, 432],
];

/* Ce code s'exécute dans Chromium. */
async function atelier([b64, R, demandes]) {
  const img = new Image();
  img.src = "data:image/png;base64," + b64;
  await img.decode();
  const S = Math.min(img.naturalWidth, img.naturalHeight);
  const toile = (w, h) => {
    const c = document.createElement("canvas");
    c.width = w; c.height = h || w;
    return c;
  };

  /* ---------- 1. Détourer ---------- */
  const tuile = toile(S);
  const gt = tuile.getContext("2d");
  gt.drawImage(img, (img.naturalWidth - S) / 2, (img.naturalHeight - S) / 2, S, S, 0, 0, S, S);
  const donnees = gt.getImageData(0, 0, S, S);
  const px = donnees.data;
  let dehors = new Uint8Array(S * S);
  const blanc = (k) => Math.min(px[4 * k], px[4 * k + 1], px[4 * k + 2]) >= 200;
  const pile = [];
  for (const k of [0, S - 1, S * (S - 1), S * S - 1]) if (blanc(k)) { dehors[k] = 1; pile.push(k); }
  while (pile.length) {
    const k = pile.pop();
    const x = k % S, y = (k - x) / S;
    if (x > 0 && !dehors[k - 1] && blanc(k - 1)) { dehors[k - 1] = 1; pile.push(k - 1); }
    if (x < S - 1 && !dehors[k + 1] && blanc(k + 1)) { dehors[k + 1] = 1; pile.push(k + 1); }
    if (y > 0 && !dehors[k - S] && blanc(k - S)) { dehors[k - S] = 1; pile.push(k - S); }
    if (y < S - 1 && !dehors[k + S] && blanc(k + S)) { dehors[k + S] = 1; pile.push(k + S); }
  }
  for (let passe = 0; passe < R.RONGER; passe++) {
    const suite = dehors.slice();
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const k = y * S + x;
      if (dehors[k]) continue;
      if ((x > 0 && dehors[k - 1]) || (x < S - 1 && dehors[k + 1]) ||
          (y > 0 && dehors[k - S]) || (y < S - 1 && dehors[k + S])) suite[k] = 1;
    }
    dehors = suite;
  }
  let nbDehors = 0;
  for (let k = 0; k < S * S; k++) if (dehors[k]) { px[4 * k + 3] = 0; nbDehors++; }
  gt.putImageData(donnees, 0, 0);

  /* ---------- 2. Prolonger le fond ----------
     On réduit l'image de moitié en moitié (la réduction moyenne les
     couleurs en tenant compte de la transparence), puis on remonte :
     chaque niveau est posé sur le précédent, agrandi. Là où la tuile
     manque, c'est la moyenne de ses bords qui apparaît, de plus en plus
     floue en s'éloignant. */
  function remplir(source) {
    const niveaux = [source];
    let cur = source;
    while (cur.width > 4) {
      const c = toile(Math.ceil(cur.width / 2), Math.ceil(cur.height / 2));
      const g = c.getContext("2d");
      g.imageSmoothingEnabled = true; g.imageSmoothingQuality = "high";
      g.drawImage(cur, 0, 0, c.width, c.height);
      niveaux.push(c); cur = c;
    }
    const g0 = cur.getContext("2d");
    const d0 = g0.getImageData(0, 0, cur.width, cur.height);
    for (let k = 0; k < d0.data.length; k += 4) d0.data[k + 3] = 255;
    g0.putImageData(d0, 0, 0);
    let acc = cur;
    for (let n = niveaux.length - 2; n >= 0; n--) {
      const c = toile(niveaux[n].width, niveaux[n].height);
      const g = c.getContext("2d");
      g.imageSmoothingEnabled = true; g.imageSmoothingQuality = "high";
      g.drawImage(acc, 0, 0, c.width, c.height);
      g.drawImage(niveaux[n], 0, 0);
      acc = c;
    }
    return acc;
  }
  const G = Math.round(S * 1.7);
  const grand = toile(G);
  grand.getContext("2d").drawImage(tuile, (G - S) / 2, (G - S) / 2);
  const plein = remplir(grand);

  /* Pose le logo prolongé sur un carré de N pixels, la tuile occupant la
     fraction « e » du côté. */
  function poser(g, N, e) {
    const cote = S / e, o = (G - cote) / 2;
    g.imageSmoothingEnabled = true; g.imageSmoothingQuality = "high";
    g.drawImage(plein, o, o, cote, cote, 0, 0, N, N);
  }

  const TURQUOISE = "#00C7C7", PETROLE_SOMBRE = "#0A6F7A";
  function pastille(g, N, cx, cy, r, sorte) {
    g.save();
    g.shadowColor = "rgba(5,60,70,0.35)"; g.shadowBlur = r * 0.35; g.shadowOffsetY = r * 0.08;
    g.beginPath(); g.arc(cx, cy, r, 0, Math.PI * 2);
    g.fillStyle = sorte === "panier" ? TURQUOISE : "#FFFFFF";
    g.fill();
    g.restore();
    g.save();
    if (sorte === "panier") {
      /* Un liseré blanc, fin, détache le disque de l'orbite turquoise. */
      g.lineWidth = r * 0.10; g.strokeStyle = "rgba(255,255,255,0.9)";
      g.beginPath(); g.arc(cx, cy, r * 0.95, 0, Math.PI * 2); g.stroke();
      /* Le chariot : la poignée, le panier, les deux roues. */
      g.strokeStyle = "#FFFFFF"; g.fillStyle = "#FFFFFF";
      g.lineWidth = r * 0.12; g.lineCap = "round"; g.lineJoin = "round";
      g.beginPath();
      g.moveTo(cx - r * 0.58, cy - r * 0.40);
      g.lineTo(cx - r * 0.38, cy - r * 0.40);
      g.lineTo(cx - r * 0.18, cy + r * 0.18);
      g.lineTo(cx + r * 0.40, cy + r * 0.18);
      g.lineTo(cx + r * 0.54, cy - r * 0.22);
      g.lineTo(cx - r * 0.31, cy - r * 0.22);
      g.stroke();
      g.beginPath(); g.arc(cx - r * 0.10, cy + r * 0.42, r * 0.10, 0, Math.PI * 2); g.fill();
      g.beginPath(); g.arc(cx + r * 0.32, cy + r * 0.42, r * 0.10, 0, Math.PI * 2); g.fill();
    } else {
      /* Un liseré turquoise, puis la roue dentée pétrole. */
      g.lineWidth = r * 0.09; g.strokeStyle = TURQUOISE;
      g.beginPath(); g.arc(cx, cy, r * 0.92, 0, Math.PI * 2); g.stroke();
      g.fillStyle = PETROLE_SOMBRE;
      const dents = 8, re = r * 0.62, ri = r * 0.46;
      g.beginPath();
      for (let k = 0; k < dents * 2; k++) {
        const a = (k / (dents * 2)) * Math.PI * 2;
        const rr = k % 2 === 0 ? re : ri;
        const a1 = a - Math.PI / (dents * 2) * 0.55, a2 = a + Math.PI / (dents * 2) * 0.55;
        if (k === 0) g.moveTo(cx + rr * Math.cos(a1), cy + rr * Math.sin(a1));
        else g.lineTo(cx + rr * Math.cos(a1), cy + rr * Math.sin(a1));
        g.lineTo(cx + rr * Math.cos(a2), cy + rr * Math.sin(a2));
      }
      g.closePath(); g.fill();
      g.beginPath(); g.arc(cx, cy, r * 0.20, 0, Math.PI * 2); g.fillStyle = "#FFFFFF"; g.fill();
    }
    g.restore();
  }
  /* Le centre et le rayon de la pastille, en fraction du côté : toujours
     dans la zone que le masque de la forme laisse voir. */
  const PASTILLE = {
    tuile: [0.80, 0.80, 0.13], plein: [0.80, 0.80, 0.13], maskable: [0.71, 0.71, 0.09],
    rond: [0.75, 0.75, 0.11], "premier-plan": [0.685, 0.685, 0.072],
  };

  const sorties = {};
  for (const [cle, N, forme, marquee] of demandes) {
    const c = toile(N);
    const g = c.getContext("2d");
    if (forme === "logo") {
      g.imageSmoothingEnabled = true; g.imageSmoothingQuality = "high";
      g.drawImage(tuile, 0, 0, N, N);
    } else {
      g.save();
      if (forme === "tuile") {
        const r = R.RAYON_TUILE * N;
        g.beginPath();
        g.moveTo(r, 0); g.arcTo(N, 0, N, N, r); g.arcTo(N, N, 0, N, r); g.arcTo(0, N, 0, 0, r); g.arcTo(0, 0, N, 0, r);
        g.closePath(); g.clip();
      } else if (forme === "rond") {
        g.beginPath(); g.arc(N / 2, N / 2, N / 2, 0, Math.PI * 2); g.clip();
      }
      poser(g, N, R.ECHELLE[forme]);
      g.restore();
      if (marquee) {
        const [px0, py0, pr] = PASTILLE[forme];
        pastille(g, N, px0 * N, py0 * N, pr * N, marquee);
      }
    }
    sorties[cle] = c.toDataURL("image/png");
  }
  return { sorties, bilan: { cote: S, dehors: nbDehors / (S * S) } };
}

(async () => {
  if (!fs.existsSync(SOURCE)) {
    console.error("Logo introuvable : " + SOURCE);
    process.exit(1);
  }
  const b64 = fs.readFileSync(SOURCE).toString("base64");
  const demandes = [];
  /* BIZZOO Personnel porte la même pastille que l'admin : ce sont les
     deux applications de l'équipe. (4.3.0) Le client porte la sienne : le
     chariot. */
  for (const app of ["client", "admin", "personnel"]) {
    const marquee = app === "client" ? "panier" : "reglages";
    for (const [nom, taille, forme] of CIBLES_PWA) demandes.push([app + "|pwa|" + nom, taille, forme, marquee]);
    demandes.push([app + "|pwa|logo-bizzoo-b.png", 192, "logo", false]);
    if (app === "personnel") continue;          // pas d'application Android
    for (const [densite, classique, adaptatif] of DENSITES) {
      demandes.push([app + "|" + densite + "|ic_launcher.png", classique, "tuile", marquee]);
      demandes.push([app + "|" + densite + "|ic_launcher_round.png", classique, "rond", marquee]);
      demandes.push([app + "|" + densite + "|ic_launcher_premier_plan.png", adaptatif, "premier-plan", marquee]);
      demandes.push([app + "|" + densite + "|ic_launcher_fond.png", adaptatif, "fond", false]);
    }
  }
  const chromium = chargerChromium();
  const nav = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
  const page = await nav.newPage();
  let resultat;
  try {
    resultat = await page.evaluate(atelier, [b64, { ECHELLE, RAYON_TUILE, RONGER }, demandes]);
  } finally {
    await nav.close();
  }
  const { sorties, bilan } = resultat;
  /* Le détourage n'emporte que le blanc des coins et un liseré : si la
     part « dehors » sort de cette fourchette, la source n'est pas le
     logo attendu (fond coloré, image recadrée…). */
  if (bilan.dehors < 0.02 || bilan.dehors > 0.12) {
    console.error("Détourage suspect : " + (bilan.dehors * 100).toFixed(1) + " % de l'image hors de la tuile.");
    process.exit(1);
  }
  let ecrits = 0;
  for (const [cle, url] of Object.entries(sorties)) {
    const [app, dossier, nom] = cle.split("|");
    const cible = dossier === "pwa"
      ? path.join(RACINE, app, "icons", nom)
      : path.join(RACINE, "android", "app", "src", app, "res", dossier, nom);
    fs.mkdirSync(path.dirname(cible), { recursive: true });
    const octets = Buffer.from(url.split(",")[1], "base64");
    fs.writeFileSync(cible, octets);
    ecrits++;
    if (dossier === "pwa") for (const ancien of ANCIENS_NOMS[nom] || []) {
      fs.writeFileSync(path.join(path.dirname(cible), ancien), octets);
      ecrits++;
    }
  }
  console.log("Tuile détourée : " + bilan.cote + " px de côté, " + (bilan.dehors * 100).toFixed(1) + " % rendu transparent.");
  console.log(ecrits + " icônes écrites depuis " + path.basename(SOURCE) + ".");
})().catch((err) => {
  console.error(err && err.message ? err.message : err);
  process.exit(1);
});
