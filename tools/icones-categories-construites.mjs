/* =========================================================
   Les quatre icônes de catégorie que l'image de l'enseigne n'a pas
   (3.56) : Bébé & Enfant, Sport & Loisirs, Livres & Éducation,
   Animaux. Construites dans SON style, avec SES mesures : trait de
   11 px à l'échelle de l'image (2,23 sur une grille de 48 rendue à
   237 px), bouts arrondis, bleu nuit #042149 et orange #FB5A03 — les
   couleurs relevées dans l'image elle-même.

   Rendues sur fond transparent, à l'échelle de l'image ;
   « icones-categories.py » les pose ensuite sur le même carré que
   les douze autres.

     node tools/icones-categories-construites.mjs /tmp/construites
   ========================================================= */
import { mkdirSync } from "node:fs";

let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/icones-categories-construites.mjs <dossier>");
  process.exit(2);
}
const DOSSIER = process.argv[2];
if (!DOSSIER) { console.error("Usage : node tools/icones-categories-construites.mjs <dossier>"); process.exit(2); }
mkdirSync(DOSSIER, { recursive: true });
const B = "#042149", O = "#FB5A03";
const F = 'fill="' + O + '" stroke="' + O + '"';

const ICONES = {
  /* Bébé & Enfant : une poussette, la capote en orange. */
  "bebe-enfant": `
    <path d="M10.5 22.5a11.5 11.5 0 0 1 11.5-11.5v11.5z" ${F}/>
    <path d="M10.5 22.5h22.5a10.5 10.5 0 0 1-10.5 9.8h-1.5a10.5 10.5 0 0 1-10.5-9.8z"/>
    <path d="M33 22.5l2.4-9.8a2.4 2.4 0 0 1 2.3-1.7h2.8"/>
    <path d="M17 32.3l-1 2.4M28 32.3l1 2.4"/>
    <circle cx="15.5" cy="38.2" r="3.4"/>
    <circle cx="29.5" cy="38.2" r="3.4"/>`,
  /* Sport & Loisirs : un ballon, le pentagone du centre en orange. */
  "sport-loisirs": `
    <circle cx="24" cy="24" r="16.5"/>
    <path d="M24 17.8 29.9 22.1 27.6 29 20.4 29 18.1 22.1z" ${F}/>
    <path d="M24 17.8V12.8M31.2 9.2 24 12.8 16.8 9.2M29.9 22.1l4.8-1.6M40.3 26.3l-5.6-5.8 1.2-8M27.6 29l3 4.1M26.9 40.2l3.7-7.1 8-1.4M20.4 29l-3 4.1M9.4 31.7l8 1.4 3.7 7.1M18.1 22.1l-4.8-1.6M12.1 12.5l1.2 8-5.6 5.8"/>`,
  /* Livres, Éducation & Fournitures : un livre ouvert, le signet en orange. */
  "livres-education": `
    <path d="M24 13.5c-3.8-2.6-9.2-3.5-15.5-3.2v25.4c6.3-.3 11.7.6 15.5 3.2 3.8-2.6 9.2-3.5 15.5-3.2V10.3c-6.3-.3-11.7.6-15.5 3.2z"/>
    <path d="M24 13.5v25.4"/>
    <path d="M30.6 10.9v10.2l2.5-2.1 2.5 2.1V10.4" ${F}/>`,
  /* Animaux : une patte, les doigts en orange. */
  "animaux": `
    <path d="M24 24.5c4.8 0 8.5 3.6 8.5 7.6 0 3-2.3 5.1-5.3 5.1-1.4 0-2.1-.6-3.2-.6s-1.8.6-3.2.6c-3 0-5.3-2.1-5.3-5.1 0-4 3.7-7.6 8.5-7.6z"/>
    <ellipse cx="13.2" cy="21.8" rx="2.9" ry="3.7" transform="rotate(-20 13.2 21.8)" ${F}/>
    <ellipse cx="19.6" cy="13.9" rx="2.9" ry="3.9" ${F}/>
    <ellipse cx="28.4" cy="13.9" rx="2.9" ry="3.9" ${F}/>
    <ellipse cx="34.8" cy="21.8" rx="2.9" ry="3.7" transform="rotate(20 34.8 21.8)" ${F}/>`,
};

const nav = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
const page = await nav.newPage({ viewport: { width: 300, height: 300 }, deviceScaleFactor: 1 });
for (const [nom, corps] of Object.entries(ICONES)) {
  await page.setContent(`<!doctype html><style>html,body{margin:0;background:transparent}
    svg{display:block;fill:none;stroke:${B};stroke-width:2.23;stroke-linecap:round;stroke-linejoin:round}</style>
    <svg id="i" width="237" height="237" viewBox="0 0 48 48">${corps}</svg>`);
  await (await page.$("#i")).screenshot({ path: DOSSIER + "/" + nom + ".png", omitBackground: true });
  console.log(nom);
}
await nav.close();
