/* =========================================================
   Les pictogrammes des catégories aux couleurs de BIZZOO Market (4.0.0)
   =========================================================
   Les 34 pictogrammes (client/img/pictos, admin/img/pictos) étaient
   dessinés en bleu nuit et orange, les couleurs de l'ancienne charte.
   On ne les redessine pas : on change leurs DEUX couleurs, pixel par
   pixel, en gardant le dessin, l'ombrage et la transparence :

     - l'ORANGE (teinte 0-50°, saturée) devient le turquoise signature
       #00CFCB, à la même clarté relative ;
     - le BLEU NUIT (teinte 190-260°) devient l'anthracite de la
       charte : teinte 200°, saturation réduite, même clarté.

   Le reste (gris, blancs, reflets) ne bouge pas. Les originaux sont
   gardés hors des applications, dans « docs/pictos-avant-4.0.0/», la
   première fois seulement : relancer le script repart toujours d'eux.

     PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/recolorer-pictos.mjs
   ========================================================= */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const RACINE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
const SOURCE = path.join(RACINE, "client", "img", "pictos");
const ORIGINAUX = path.join(RACINE, "docs", "pictos-avant-4.0.0");
const CIBLES = [path.join(RACINE, "client", "img", "pictos"), path.join(RACINE, "admin", "img", "pictos")];

if (!fs.existsSync(ORIGINAUX)) {
  fs.mkdirSync(ORIGINAUX, { recursive: true });
  for (const f of fs.readdirSync(SOURCE)) if (f.endsWith(".png")) fs.copyFileSync(path.join(SOURCE, f), path.join(ORIGINAUX, f));
}
const fichiers = fs.readdirSync(ORIGINAUX).filter((f) => f.endsWith(".png")).sort();

async function recolorer(b64) {
  const img = new Image();
  img.src = "data:image/png;base64," + b64;
  await img.decode();
  const c = document.createElement("canvas");
  c.width = img.naturalWidth; c.height = img.naturalHeight;
  const g = c.getContext("2d");
  g.drawImage(img, 0, 0);
  const d = g.getImageData(0, 0, c.width, c.height);
  const p = d.data;
  const versHsl = (r, v, b) => {
    r /= 255; v /= 255; b /= 255;
    const max = Math.max(r, v, b), min = Math.min(r, v, b), l = (max + min) / 2;
    if (max === min) return [0, 0, l];
    const e = max - min, s = l > 0.5 ? e / (2 - max - min) : e / (max + min);
    let h = max === r ? (v - b) / e + (v < b ? 6 : 0) : max === v ? (b - r) / e + 2 : (r - v) / e + 4;
    return [h * 60, s, l];
  };
  const versRvb = (h, s, l) => {
    const k = (n) => (n + h / 30) % 12, a = s * Math.min(l, 1 - l);
    const f = (n) => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
    return [f(0) * 255, f(8) * 255, f(4) * 255];
  };
  // Le turquoise #00CFCB : teinte 179°, saturation 1, clarté 0,406.
  const TURQ = { h: 179, s: 1, l: 0.406 };
  let orange = 0, nuit = 0;
  for (let i = 0; i < p.length; i += 4) {
    if (p[i + 3] === 0) continue;
    const [h, s, l] = versHsl(p[i], p[i + 1], p[i + 2]);
    let rvb = null;
    if (s > 0.35 && (h <= 50 || h >= 345) && l > 0.12) {
      // La clarté de l'orange (#F25604 : 0,48) se reporte sur le turquoise.
      const ll = Math.max(0.08, Math.min(0.92, TURQ.l * (l / 0.48)));
      rvb = versRvb(TURQ.h, TURQ.s, ll);
      orange++;
    } else if (s > 0.15 && h >= 190 && h <= 260) {
      rvb = versRvb(200, Math.min(s, 1) * 0.42, l);
      nuit++;
    }
    if (rvb) { p[i] = rvb[0]; p[i + 1] = rvb[1]; p[i + 2] = rvb[2]; }
  }
  g.putImageData(d, 0, 0);
  return { url: c.toDataURL("image/png"), orange, nuit };
}

const nav = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
const page = await nav.newPage();
let n = 0;
for (const f of fichiers) {
  const b64 = fs.readFileSync(path.join(ORIGINAUX, f)).toString("base64");
  const r = await page.evaluate(recolorer, b64);
  const octets = Buffer.from(r.url.split(",")[1], "base64");
  for (const dossier of CIBLES) {
    fs.mkdirSync(dossier, { recursive: true });
    fs.writeFileSync(path.join(dossier, f), octets);
  }
  n++;
  console.log(f.padEnd(26) + " orange→turquoise " + String(r.orange).padStart(5) + " px, bleu nuit→anthracite " + String(r.nuit).padStart(6) + " px");
}
await nav.close();
console.log("\n" + n + " pictogrammes recolorés, dans client/ et admin/.");
