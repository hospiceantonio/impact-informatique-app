/* =========================================================
   Génère les icônes PNG des deux applications PWA :
   le « i » blanc du logo IMPACT avec ses ondes, sur fond
   bleu (client) et bleu nuit/rouge (admin).
   Aucune dépendance : rendu par fonctions de distance
   + encodeur PNG maison.
   Usage : node tools/make-icons.js
   ========================================================= */
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

/* ---------- Encodeur PNG minimal (RGBA, sans entrelacement) ---------- */
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

function encodePNG(width, height, rgba) {
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0; // filtre "None"
    rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // profondeur
  ihdr[9] = 6; // RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

/* ---------- Fonctions de distance (coordonnées normalisées 0..1) ---------- */
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const mix = (a, b, t) => a + (b - a) * t;

function sdCircle(px, py, cx, cy, r) {
  return Math.hypot(px - cx, py - cy) - r;
}

function sdRoundedBox(px, py, cx, cy, halfW, halfH, r) {
  const qx = Math.abs(px - cx) - halfW + r;
  const qy = Math.abs(py - cy) - halfH + r;
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
}

/** Arc d'onde : anneau limité à un secteur angulaire (angles en radians). */
function sdArc(px, py, cx, cy, rayon, epaisseur, angleCentre, demiOuverture) {
  const dx = px - cx, dy = py - cy;
  const anneau = Math.abs(Math.hypot(dx, dy) - rayon) - epaisseur;
  let angle = Math.atan2(dy, dx) - angleCentre;
  while (angle > Math.PI) angle -= 2 * Math.PI;
  while (angle < -Math.PI) angle += 2 * Math.PI;
  const horsSecteur = Math.abs(angle) - demiOuverture;
  // Hors du secteur : on éloigne artificiellement (coupe franche adoucie par l'AA).
  return Math.max(anneau, horsSecteur * rayon);
}

/* ---------- Le motif : « i » penché + ondes ---------- */

const PENTE = 0.14;           // italique ~8°
const TIGE = { cx: 0.50, cy: 0.615, halfW: 0.058, halfH: 0.165, r: 0.058 };
const POINT = { cx: 0.535, cy: 0.335, r: 0.068 };
const ONDES = [
  { rayon: 0.145, epaisseur: 0.026 },
  { rayon: 0.235, epaisseur: 0.026 },
];
const ONDE_ANGLE = -Math.PI / 4;      // vers le haut-droit, comme le logo
const ONDE_OUVERTURE = 0.62;          // ~35° de part et d'autre

function motif(mx, my) {
  /* Coordonnées penchées pour l'italique. */
  const sx = mx + (my - TIGE.cy) * PENTE;
  const dTige = sdRoundedBox(sx, my, TIGE.cx, TIGE.cy, TIGE.halfW, TIGE.halfH, TIGE.r);
  const sxPoint = mx + (my - POINT.cy) * PENTE;
  const dPoint = sdCircle(sxPoint, my, POINT.cx, POINT.cy, POINT.r);
  let d = Math.min(dTige, dPoint);
  for (const onde of ONDES) {
    d = Math.min(d, sdArc(mx, my, POINT.cx + (POINT.cy - POINT.cy) * PENTE, POINT.cy,
      onde.rayon, onde.epaisseur, ONDE_ANGLE, ONDE_OUVERTURE));
  }
  return d;
}

/* ---------- Palettes ---------- */

const PALETTES = {
  client: { haut: [61, 155, 238], bas: [8, 62, 134] },     // bleus du logo
  admin: { haut: [235, 77, 82], bas: [150, 12, 17] },      // rouge « imbattables »
};

function over(dst, src, alpha) {
  dst[0] = mix(dst[0], src[0], alpha);
  dst[1] = mix(dst[1], src[1], alpha);
  dst[2] = mix(dst[2], src[2], alpha);
}

/**
 * @param {number} size       côté en pixels
 * @param {boolean} maskable  true = fond plein bord à bord + motif réduit (zone sûre)
 * @param {{haut:number[],bas:number[]}} palette
 */
function renderIcon(size, maskable, palette) {
  const buf = Buffer.alloc(size * size * 4);
  const aa = 1.1 / size; // lissage ≈ 1 pixel
  const scale = maskable ? 0.72 : 1;
  const bgRadius = maskable ? 0.5 : 0.22;

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const px = (x + 0.5) / size;
      const py = (y + 0.5) / size;
      // Motif recentré/réduit pour respecter la zone sûre des icônes masquables.
      const mx = 0.5 + (px - 0.5) / scale;
      const my = 0.5 + (py - 0.5) / scale;

      const bgTint = clamp(px * 0.35 + py * 0.75, 0, 1);
      const color = [
        mix(palette.haut[0], palette.bas[0], bgTint),
        mix(palette.haut[1], palette.bas[1], bgTint),
        mix(palette.haut[2], palette.bas[2], bgTint),
      ];

      const dBg = sdRoundedBox(px, py, 0.5, 0.5, 0.5, 0.5, bgRadius);
      const bgAlpha = clamp(0.5 - dBg / aa, 0, 1);

      // Halo doux derrière le motif
      const dHalo = sdCircle(mx, my, 0.5, 0.5, 0.42);
      over(color, [255, 255, 255], clamp(0.5 - dHalo / 0.34, 0, 1) * 0.08);

      // Le « i » et ses ondes, en blanc
      const dMotif = motif(mx, my);
      over(color, [255, 255, 255], clamp(0.5 - dMotif / aa, 0, 1));

      const i = (y * size + x) * 4;
      buf[i] = Math.round(color[0]);
      buf[i + 1] = Math.round(color[1]);
      buf[i + 2] = Math.round(color[2]);
      buf[i + 3] = Math.round(bgAlpha * 255);
    }
  }
  return encodePNG(size, size, buf);
}

/**
 * Premier plan d'icône adaptative Android : motif blanc sur fond
 * transparent, réduit dans la zone sûre (66/108 du canevas).
 */
function renderForeground(size) {
  const buf = Buffer.alloc(size * size * 4);
  const aa = 1.1 / size;
  const scale = 0.52;

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const px = (x + 0.5) / size;
      const py = (y + 0.5) / size;
      const mx = 0.5 + (px - 0.5) / scale;
      const my = 0.5 + (py - 0.5) / scale;
      const alpha = clamp(0.5 - motif(mx, my) / aa, 0, 1);
      const i = (y * size + x) * 4;
      buf[i] = 255;
      buf[i + 1] = 255;
      buf[i + 2] = 255;
      buf[i + 3] = Math.round(alpha * 255);
    }
  }
  return encodePNG(size, size, buf);
}

/* ---------- Génération ---------- */

const CIBLES = [
  ["icon-192.png", 192, false],
  ["icon-512.png", 512, false],
  ["icon-maskable-512.png", 512, true],
  ["apple-touch-icon.png", 180, true],
];

/* Icônes Android : classique (48dp) et premier plan adaptatif (108dp). */
const DENSITES = [
  ["mipmap-mdpi", 48, 108],
  ["mipmap-hdpi", 72, 162],
  ["mipmap-xhdpi", 96, 216],
  ["mipmap-xxhdpi", 144, 324],
  ["mipmap-xxxhdpi", 192, 432],
];

for (const app of ["client", "admin"]) {
  const dossier = path.join(__dirname, "..", app, "icons");
  fs.mkdirSync(dossier, { recursive: true });
  for (const [nom, size, maskable] of CIBLES) {
    const png = renderIcon(size, maskable, PALETTES[app]);
    fs.writeFileSync(path.join(dossier, nom), png);
    console.log(app + "/" + nom + " — " + size + "×" + size + " — " + (png.length / 1024).toFixed(1) + " Ko");
  }

  const resAndroid = path.join(__dirname, "..", "android", "app", "src", app, "res");
  for (const [densite, tailleIcone, taillePremierPlan] of DENSITES) {
    const dossierDensite = path.join(resAndroid, densite);
    fs.mkdirSync(dossierDensite, { recursive: true });
    fs.writeFileSync(path.join(dossierDensite, "ic_launcher.png"),
      renderIcon(tailleIcone, true, PALETTES[app]));
    fs.writeFileSync(path.join(dossierDensite, "ic_launcher_round.png"),
      renderIcon(tailleIcone, true, PALETTES[app]));
    fs.writeFileSync(path.join(dossierDensite, "ic_launcher_premier_plan.png"),
      renderForeground(taillePremierPlan));
  }
  console.log(app + " — icônes Android écrites dans android/app/src/" + app + "/res/mipmap-*");
}
