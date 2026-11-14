/* =========================================================
   Fabrique les icônes des applications BIZZOO Market (4.0.0)
   à partir du monogramme officiel (tools/bizzoo-monogramme.png) :
   le B blanc, son anneau turquoise et son triangle anthracite,
   détouré, sans l'ombre portée de la planche d'origine.

   On ne reprend PAS l'icône 1024 du kit iOS telle quelle : son
   monogramme déborde du disque que les lanceurs Android laissent
   voir, et elle garde l'ombre sous le triangle. Toutes les formes
   sont recomposées ici, avec la même recette :

     - le FOND : l'anthracite de la charte (#0F1E26), éclairé d'un
       halo à peine plus clair en haut — celui des écrans de la DA ;
     - le MOTIF : le monogramme, centré sur sa boîte, à la taille
       que chaque forme permet.

   Les formes :
     - tuile    (PWA 192/512, Android d'avant la version 8) : coins
                arrondis compris dans l'image ;
     - plein    (iPhone, « apple-touch-icon ») : carré plein, que
                l'iPhone arrondit lui-même ;
     - maskable (PWA installée sur Android) : le motif tient dans le
                disque de 80 % que tout masque respecte ;
     - rond     (Android, lanceurs à icônes rondes) ;
     - adaptative (Android 8 et plus) : deux calques, le fond et le
                motif, dans la zone sûre de 66 dp sur 108.

   L'admin et BIZZOO Personnel reçoivent la même icône, marquée d'une
   pastille turquoise « réglages » en bas à droite — le coin que le
   monogramme laisse libre : sur un même téléphone, on distingue les
   applications d'un coup d'œil. Le LOGO (icons/logo-bizzoo-market.png), lui,
   est le monogramme seul, sans fond ni pastille : la marque, pas
   l'icône d'une application.

   Enfin, la petite icône de la barre de notifications : la
   silhouette du B et de son anneau (les parties claires du
   monogramme), tracée en contour. Android n'en garde que la forme.

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
const SOURCE = path.join(__dirname, "bizzoo-monogramme.png");

/* La largeur du motif, en fraction du côté de l'image, pour chaque forme.
   Le monogramme est un triangle : sa boîte est bien plus grande que sa
   surface, et ses coins sont vides. */
const LARGEUR_MOTIF = { tuile: 0.70, plein: 0.70, maskable: 0.60, rond: 0.62, "premier-plan": 0.50, logo: 0.96 };
/* Le rayon des coins de la tuile, en fraction du côté. */
const RAYON_TUILE = 0.225;

/* (4.2.0) DES NOMS NEUFS POUR LE LOGO DE BIZZOO MARKET. L'hébergement
   laisse un navigateur garder une image une semaine : sous l'ancien nom,
   la vitrine et les applications montraient encore l'ancien logo, gardé
   en mémoire. Sous un nom neuf, aucun cache ne peut le servir. Les ANCIENS
   NOMS sont écrits aussi, avec le nouveau logo : une adresse déjà partie
   (un e-mail, une icône d'écran d'accueil) le montre aussi. */
const CIBLES_PWA = [
  ["icone-market-192.png", 192, "tuile"],
  ["icone-market-512.png", 512, "tuile"],
  ["icone-market-maskable-512.png", 512, "maskable"],
  ["apple-touch-icon-market.png", 180, "plein"],
];
const ANCIENS_NOMS = {
  "icone-market-192.png": "icon-192.png",
  "icone-market-512.png": "icon-512.png",
  "icone-market-maskable-512.png": "icon-maskable-512.png",
  "apple-touch-icon-market.png": "apple-touch-icon.png",
  "logo-bizzoo-market.png": "logo-bizzoo.png",
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
  const W = img.naturalWidth, H = img.naturalHeight;

  const ANTHRACITE = "#0F1E26", HALO = "#1B3540", TURQUOISE = "#00CFCB";

  function fond(g, N, forme) {
    g.save();
    if (forme === "tuile") {
      const r = R.RAYON_TUILE * N;
      g.beginPath();
      g.moveTo(r, 0); g.arcTo(N, 0, N, N, r); g.arcTo(N, N, 0, N, r); g.arcTo(0, N, 0, 0, r); g.arcTo(0, 0, N, 0, r);
      g.closePath(); g.clip();
    } else if (forme === "rond") {
      g.beginPath(); g.arc(N / 2, N / 2, N / 2, 0, Math.PI * 2); g.clip();
    }
    g.fillStyle = ANTHRACITE;
    g.fillRect(0, 0, N, N);
    const halo = g.createRadialGradient(N * 0.5, N * 0.28, 0, N * 0.5, N * 0.28, N * 0.75);
    halo.addColorStop(0, HALO);
    halo.addColorStop(1, "rgba(15,30,38,0)");
    g.fillStyle = halo;
    g.fillRect(0, 0, N, N);
    g.restore();
  }

  function motif(g, N, largeur, dy) {
    const w = N * largeur, h = w * H / W;
    g.imageSmoothingQuality = "high";
    g.drawImage(img, (N - w) / 2, (N - h) / 2 + (dy || 0) * N, w, h);
  }

  /* La pastille « réglages » : un disque turquoise, une roue dentée anthracite. */
  function pastille(g, N, cx, cy, r) {
    g.save();
    g.beginPath(); g.arc(cx, cy, r * 1.14, 0, Math.PI * 2); g.fillStyle = ANTHRACITE; g.fill();
    g.beginPath(); g.arc(cx, cy, r, 0, Math.PI * 2); g.fillStyle = TURQUOISE; g.fill();
    g.fillStyle = ANTHRACITE;
    const dents = 8, re = r * 0.66, ri = r * 0.48;
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
    g.beginPath(); g.arc(cx, cy, r * 0.22, 0, Math.PI * 2); g.fillStyle = TURQUOISE; g.fill();
    g.restore();
  }
  const PASTILLE = {
    tuile: [0.80, 0.80, 0.13], plein: [0.80, 0.80, 0.13], maskable: [0.73, 0.73, 0.095],
    rond: [0.75, 0.75, 0.11], "premier-plan": [0.70, 0.70, 0.085],
  };

  const sorties = {};
  for (const [cle, N, forme, marquee] of demandes) {
    const c = document.createElement("canvas");
    c.width = N; c.height = N;
    const g = c.getContext("2d");
    if (forme === "fond") {
      fond(g, N, "fond");
    } else if (forme === "logo") {
      motif(g, N, R.LARGEUR_MOTIF.logo, 0);
    } else {
      if (forme !== "premier-plan") fond(g, N, forme);
      motif(g, N, R.LARGEUR_MOTIF[forme], forme === "premier-plan" ? 0 : -0.01);
      if (marquee) {
        const [px, py, pr] = PASTILLE[forme];
        pastille(g, N, px * N, py * N, pr * N);
      }
    }
    sorties[cle] = c.toDataURL("image/png");
  }

  /* ---------- La silhouette de la barre de notifications ----------
     Les parties claires du monogramme : le B blanc et l'anneau
     turquoise. Le triangle anthracite n'y est pas : sur la barre de
     notifications, il ne ferait qu'un pavé. */
  const N = 512;
  const c = document.createElement("canvas");
  c.width = N; c.height = N;
  const g = c.getContext("2d");
  const w = N * 0.96, h = w * H / W;
  g.drawImage(img, (N - w) / 2, (N - h) / 2, w, h);
  const px = g.getImageData(0, 0, N, N).data;
  const alpha = new Float32Array(N * N);
  for (let k = 0; k < N * N; k++) {
    const r = px[4 * k], v = px[4 * k + 1], b = px[4 * k + 2], a = px[4 * k + 3] / 255;
    /* Le blanc du B (les trois composantes hautes), ou le turquoise
       franc de l'anneau (rouge presque nul, vert haut). Le reflet
       bleu-vert du haut du triangle, pâle, n'est ni l'un ni l'autre. */
    const blanc = Math.min(r, v, b) / 255;
    const turquoise = r < 90 ? v / 255 : 0;
    const clair = Math.max(blanc, turquoise);
    alpha[k] = a * Math.max(0, Math.min(1, (clair - 0.6) / 0.15));
  }
  const CELLULE = 4;
  let bx0 = N, by0 = N, bx1 = 0, by1 = 0;
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    if (alpha[y * N + x] < 0.5) continue;
    bx0 = Math.min(bx0, x); by0 = Math.min(by0, y); bx1 = Math.max(bx1, x); by1 = Math.max(by1, y);
  }
  const gx0 = bx0 - 2 * CELLULE, gy0 = by0 - 2 * CELLULE;
  const GW = Math.ceil((bx1 - gx0 + 2 * CELLULE) / CELLULE) + 1;
  const GH = Math.ceil((by1 - gy0 + 2 * CELLULE) / CELLULE) + 1;
  const champ = new Float32Array(GW * GH);
  for (let j = 0; j < GH; j++) for (let i = 0; i < GW; i++) {
    let s = 0, n = 0;
    for (let dy = 0; dy < CELLULE; dy++) for (let dx = 0; dx < CELLULE; dx++) {
      const x = gx0 + i * CELLULE + dx, y = gy0 + j * CELLULE + dy;
      n++;
      if (x < 0 || y < 0 || x >= N || y >= N) continue;
      s += alpha[y * N + x];
    }
    champ[j * GW + i] = s / n;
  }
  const val = (i, j) => (i < 0 || j < 0 || i >= GW || j >= GH ? 0 : champ[j * GW + i]);
  const SEUIL = 0.5;
  const pointArete = (cleA) => {
    const [t, a, b] = cleA.split(":");
    const i = +a, j = +b;
    if (t === "h") { const v0 = val(i, j), v1 = val(i + 1, j); return [i + (SEUIL - v0) / (v1 - v0), j]; }
    const v0 = val(i, j), v1 = val(i, j + 1);
    return [i, j + (SEUIL - v0) / (v1 - v0)];
  };
  const liens = new Map();
  const relier = (a, b) => {
    if (!liens.has(a)) liens.set(a, []);
    if (!liens.has(b)) liens.set(b, []);
    liens.get(a).push(b); liens.get(b).push(a);
  };
  for (let j = -1; j < GH; j++) for (let i = -1; i < GW; i++) {
    const tl = val(i, j) >= SEUIL, tr = val(i + 1, j) >= SEUIL, br = val(i + 1, j + 1) >= SEUIL, bl = val(i, j + 1) >= SEUIL;
    const cas = (tl ? 8 : 0) | (tr ? 4 : 0) | (br ? 2 : 0) | (bl ? 1 : 0);
    const Hh = "h:" + i + ":" + j, B = "h:" + i + ":" + (j + 1), G = "v:" + i + ":" + j, D = "v:" + (i + 1) + ":" + j;
    const centre = (val(i, j) + val(i + 1, j) + val(i + 1, j + 1) + val(i, j + 1)) / 4 >= SEUIL;
    switch (cas) {
      case 1: case 14: relier(G, B); break;
      case 2: case 13: relier(B, D); break;
      case 3: case 12: relier(G, D); break;
      case 4: case 11: relier(Hh, D); break;
      case 6: case 9: relier(Hh, B); break;
      case 7: case 8: relier(G, Hh); break;
      case 5: if (centre) { relier(G, Hh); relier(B, D); } else { relier(G, B); relier(Hh, D); } break;
      case 10: if (centre) { relier(Hh, D); relier(G, B); } else { relier(G, Hh); relier(B, D); } break;
      default: break;
    }
  }
  const vues = new Set();
  const boucles = [];
  for (const depart of liens.keys()) {
    if (vues.has(depart)) continue;
    const boucle = [];
    let prec = null, cur = depart;
    while (cur && !vues.has(cur)) {
      vues.add(cur);
      boucle.push(pointArete(cur));
      const suivants = liens.get(cur).filter((x) => x !== prec && !vues.has(x));
      prec = cur; cur = suivants[0];
    }
    if (boucle.length > 8) boucles.push(boucle);
  }
  /* Les éclats : un contour minuscule qui n'est pas un trou d'une grande
     forme (un reflet du triangle passé au travers du seuil). */
  const aire = (b) => Math.abs(b.reduce((s, [x, y], k) => {
    const [x2, y2] = b[(k + 1) % b.length];
    return s + x * y2 - x2 * y;
  }, 0) / 2);
  const boite = (b) => b.reduce((m, [x, y]) => [Math.min(m[0], x), Math.min(m[1], y), Math.max(m[2], x), Math.max(m[3], y)],
    [Infinity, Infinity, -Infinity, -Infinity]);
  const aires = boucles.map(aire);
  const plusGrande = Math.max(...aires);
  for (let k = boucles.length - 1; k >= 0; k--) {
    if (aires[k] >= 0.04 * plusGrande) continue;
    const [x0, y0, x1, y1] = boite(boucles[k]);
    const dedans = boucles.some((b, m) => {
      if (m === k || aires[m] < 0.04 * plusGrande) return false;
      const [X0, Y0, X1, Y1] = boite(b);
      return x0 >= X0 && y0 >= Y0 && x1 <= X1 && y1 <= Y1;
    });
    if (!dedans) boucles.splice(k, 1);
  }
  function simplifier(pts, eps) {
    if (pts.length < 3) return pts;
    const [a, b] = [pts[0], pts[pts.length - 1]];
    let loin = -1, dmax = 0;
    for (let k = 1; k < pts.length - 1; k++) {
      const [x, y] = pts[k];
      const dx = b[0] - a[0], dy = b[1] - a[1];
      const l = Math.hypot(dx, dy) || 1;
      const d = Math.abs(dy * x - dx * y + b[0] * a[1] - b[1] * a[0]) / l;
      if (d > dmax) { dmax = d; loin = k; }
    }
    if (dmax <= eps) return [a, b];
    return simplifier(pts.slice(0, loin + 1), eps).slice(0, -1).concat(simplifier(pts.slice(loin), eps));
  }
  /* Le cadrage : la boîte des contours GARDÉS (en pixels), pas celle du
     masque, qui comptait encore les éclats écartés. */
  const enPixels = boucles.flat().map(([gx, gy]) => [gx0 + gx * CELLULE + CELLULE / 2, gy0 + gy * CELLULE + CELLULE / 2]);
  const [cx0, cy0, cx1, cy1] = boite(enPixels);
  const ech = 20 / Math.max(cy1 - cy0, cx1 - cx0);
  const cxm = (cx0 + cx1) / 2, cym = (cy0 + cy1) / 2;
  const versVue = (X, Y) => [12 + (X - cxm) * ech, 12 + (Y - cym) * ech];
  const f = (v) => (Math.round(v * 100) / 100).toString();
  let chemin = "", nbPoints = 0;
  for (const boucle of boucles) {
    const moitie = Math.floor(boucle.length / 2);
    const pts = simplifier(boucle.slice(0, moitie + 1), 0.45)
      .concat(simplifier(boucle.slice(moitie).concat([boucle[0]]), 0.45).slice(1, -1));
    nbPoints += pts.length;
    pts.forEach(([gx, gy], k) => {
      const [x, y] = versVue(gx0 + gx * CELLULE + CELLULE / 2, gy0 + gy * CELLULE + CELLULE / 2);
      chemin += (k ? "L" : "M") + f(x) + "," + f(y);
    });
    chemin += "Z ";
  }
  return { sorties, chemin: chemin.trim(), bilan: { boucles: boucles.length, points: nbPoints } };
}

(async () => {
  if (!fs.existsSync(SOURCE)) {
    console.error("Monogramme introuvable : " + SOURCE);
    process.exit(1);
  }
  const b64 = fs.readFileSync(SOURCE).toString("base64");
  const demandes = [];
  /* BIZZOO Personnel porte la même pastille que l'admin : ce sont les
     deux applications de l'équipe. */
  for (const app of ["client", "admin", "personnel"]) {
    const marquee = app !== "client";
    for (const [nom, taille, forme] of CIBLES_PWA) demandes.push([app + "|pwa|" + nom, taille, forme, marquee]);
    demandes.push([app + "|pwa|logo-bizzoo-market.png", 192, "logo", false]);
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
    resultat = await page.evaluate(atelier, [b64, { LARGEUR_MOTIF, RAYON_TUILE }, demandes]);
  } finally {
    await nav.close();
  }
  const { sorties, chemin, bilan } = resultat;
  let ecrits = 0;
  for (const [cle, url] of Object.entries(sorties)) {
    const [app, dossier, nom] = cle.split("|");
    const cible = dossier === "pwa"
      ? path.join(RACINE, app, "icons", nom)
      : path.join(RACINE, "android", "app", "src", app, "res", dossier, nom);
    fs.mkdirSync(path.dirname(cible), { recursive: true });
    fs.writeFileSync(cible, Buffer.from(url.split(",")[1], "base64"));
    ecrits++;
    if (dossier === "pwa" && ANCIENS_NOMS[nom]) {
      fs.writeFileSync(path.join(path.dirname(cible), ANCIENS_NOMS[nom]), Buffer.from(url.split(",")[1], "base64"));
      ecrits++;
    }
  }
  const notif = path.join(RACINE, "android", "app", "src", "main", "res", "drawable", "ic_notification.xml");
  fs.writeFileSync(notif,
    '<?xml version="1.0" encoding="utf-8"?>\n' +
    "<!-- Icône de la barre de notifications : le B de BIZZOO Market et son\n" +
    "     anneau. Android n'en garde que la silhouette, en blanc : les trous\n" +
    "     du B restent des trous (fillType evenOdd).\n" +
    "     Fichier produit par tools/make-icons.js depuis\n" +
    "     tools/bizzoo-monogramme.png : ne pas le retoucher à la main. -->\n" +
    '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n' +
    '    android:width="24dp"\n' +
    '    android:height="24dp"\n' +
    '    android:viewportWidth="24"\n' +
    '    android:viewportHeight="24">\n' +
    "    <path\n" +
    '        android:fillColor="#FFFFFFFF"\n' +
    '        android:fillType="evenOdd"\n' +
    '        android:pathData="' + chemin + '" />\n' +
    "</vector>\n");
  console.log("Silhouette des notifications : " + bilan.boucles + " contours, " + bilan.points + " points.");
  console.log(ecrits + " icônes écrites depuis " + path.basename(SOURCE) + ".");
})().catch((err) => {
  console.error(err && err.message ? err.message : err);
  process.exit(1);
});
