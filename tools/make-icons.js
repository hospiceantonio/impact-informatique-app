/* =========================================================
   Fabrique les icônes des deux applications à partir de
   l'œuvre officielle BIZZOO (tools/bizzoo-icone.jpg) :
   le sac de courses qui dessine un B, le chariot blanc et
   les traits de vitesse, sur le bleu de la marque avec la
   vague orange.

   Ce que le script produit, pour chaque application :
   - les icônes PWA (192, 512, maskable, apple-touch) ;
   - les icônes Android classiques et adaptatives (fond +
     premier plan), toutes densités.

   L'application admin reçoit la même œuvre, marquée d'une
   pastille « réglages » : les deux applications vivent sur
   le même téléphone, on doit les distinguer d'un coup d'œil.

   Le fond de l'œuvre est prolongé au-delà du carré arrondi
   pour que les masques d'Android (rond, carré, goutte) ne
   découvrent jamais de coin vide.

   Dépendance : Chromium, piloté par Playwright — il décode
   le JPEG et rééchantillonne proprement.
   Usage : node tools/make-icons.js
   ========================================================= */
const fs = require("fs");
const path = require("path");

let chromium;
try {
  ({ chromium } = require("playwright"));
} catch (e) {
  try {
    ({ chromium } = require("/opt/node22/lib/node_modules/playwright"));
  } catch (e2) {
    console.error("Playwright est nécessaire : npm i -g playwright");
    process.exit(1);
  }
}

const RACINE = path.join(__dirname, "..");
const SOURCE = path.join(__dirname, "bizzoo-icone.jpg");

/* Emprise du motif dans l'œuvre (fractions du côté) : traits de
   vitesse à gauche, panse du B à droite, anse en haut, chariot en
   bas. Sert à centrer le motif dans la zone sûre des icônes
   adaptatives, car il n'est pas centré dans l'œuvre d'origine. */
const MOTIF = { x0: 0.118, y0: 0.116, x1: 0.834, y1: 0.816 };

/* Icônes PWA. */
const CIBLES_PWA = [
  ["icon-192.png", 192, "carre-arrondi"],
  ["icon-512.png", 512, "carre-arrondi"],
  ["icon-maskable-512.png", 512, "maskable"],
  ["apple-touch-icon.png", 180, "plein"],
];

/* Android : côté de l'icône classique (48 dp) et du calque adaptatif (108 dp). */
const DENSITES = [
  ["mipmap-mdpi", 48, 108],
  ["mipmap-hdpi", 72, 162],
  ["mipmap-xhdpi", 96, 216],
  ["mipmap-xxhdpi", 144, 324],
  ["mipmap-xxxhdpi", 192, 432],
];

/* Ce code s'exécute dans Chromium : il décode l'œuvre, prolonge son
   fond, puis dessine chaque variante demandée. */
async function atelier([b64, MOTIF, demandes]) {
  const img = new Image();
  img.src = "data:image/jpeg;base64," + b64;
  await img.decode();

  const N = img.width;
  const source = document.createElement("canvas");
  source.width = N;
  source.height = N;
  const sctx = source.getContext("2d");
  sctx.drawImage(img, 0, 0);
  const im = sctx.getImageData(0, 0, N, N);
  const d = im.data;

  /* Le carré arrondi : un pixel en fait partie s'il est franchement
     coloré. Le blanc du pourtour et son ombre grise sont gris neutres,
     ils tombent d'eux-mêmes. */
  let masque = new Uint8Array(N * N);
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      const i = (y * N + x) * 4;
      const mx = Math.max(d[i], d[i + 1], d[i + 2]);
      const mn = Math.min(d[i], d[i + 1], d[i + 2]);
      masque[y * N + x] = mx - mn > 45 ? 1 : 0;
    }
  }

  /* Érosion : on recule franchement du bord pour ne prolonger que des
     couleurs pleines, jamais le liseré adouci ni l'ombre portée. */
  const RECUL = Math.round(N * 0.028);
  const erode = new Uint8Array(N * N);
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      if (!masque[y * N + x]) continue;
      let plein = 1;
      for (let k = 0; k < 4 && plein; k++) {
        const nx = x + [RECUL, -RECUL, 0, 0][k];
        const ny = y + [0, 0, RECUL, -RECUL][k];
        if (nx < 0 || ny < 0 || nx >= N || ny >= N || !masque[ny * N + nx]) plein = 0;
      }
      erode[y * N + x] = plein;
    }
  }
  masque = erode;

  /* Prolongement : chaque ligne s'étire depuis son premier et son
     dernier pixel franc ; au-dessus et au-dessous, on recopie la
     ligne pleine la plus proche. Le raccord est invisible parce que
     le fond de l'œuvre est un dégradé lisse. */
  const copie = (src, dst) => {
    d[dst] = d[src];
    d[dst + 1] = d[src + 1];
    d[dst + 2] = d[src + 2];
  };
  const pleines = [];
  for (let y = 0; y < N; y++) {
    let a = -1;
    let b = -1;
    for (let x = 0; x < N; x++) {
      if (masque[y * N + x]) {
        if (a < 0) a = x;
        b = x;
      }
    }
    if (a < 0) continue;
    pleines.push(y);
    for (let x = 0; x < a; x++) copie((y * N + a) * 4, (y * N + x) * 4);
    for (let x = b + 1; x < N; x++) copie((y * N + b) * 4, (y * N + x) * 4);
  }
  const yHaut = pleines[0];
  const yBas = pleines[pleines.length - 1];
  for (let y = 0; y < yHaut; y++) for (let x = 0; x < N; x++) copie((yHaut * N + x) * 4, (y * N + x) * 4);
  for (let y = yBas + 1; y < N; y++) for (let x = 0; x < N; x++) copie((yBas * N + x) * 4, (y * N + x) * 4);
  for (let i = 3; i < d.length; i += 4) d[i] = 255;
  sctx.putImageData(im, 0, 0);

  /* Centre du motif, pour le poser au centre de la tuile. */
  const centreMotifX = (MOTIF.x0 + MOTIF.x1) / 2;
  const centreMotifY = (MOTIF.y0 + MOTIF.y1) / 2;

  /* Dessine l'œuvre à l'échelle voulue, motif centré, le fond
     prolongé jusqu'aux bords par étirement des bandes de rive. */
  function poser(ctx, taille, echelle) {
    const cote = taille * echelle;
    const x = taille / 2 - cote * centreMotifX;
    const y = taille / 2 - cote * centreMotifY;
    const resteX = taille - (x + cote);
    const resteY = taille - (y + cote);
    /* Rives : une colonne (ou ligne) source étirée vers l'extérieur. */
    if (x > 0) ctx.drawImage(source, 0, 0, 1, N, 0, y, x + 1, cote);
    if (y > 0) ctx.drawImage(source, 0, 0, N, 1, x, 0, cote, y + 1);
    if (resteX > 0) ctx.drawImage(source, N - 1, 0, 1, N, x + cote - 1, y, resteX + 1, cote);
    if (resteY > 0) ctx.drawImage(source, 0, N - 1, N, 1, x, y + cote - 1, cote, resteY + 1);
    /* Coins : le pixel d'angle étiré. */
    const coin = (sx, sy, dx, dy, dw, dh) => {
      if (dw > 0 && dh > 0) ctx.drawImage(source, sx, sy, 1, 1, dx, dy, dw, dh);
    };
    coin(0, 0, 0, 0, x + 1, y + 1);
    coin(N - 1, 0, x + cote - 1, 0, resteX + 1, y + 1);
    coin(0, N - 1, 0, y + cote - 1, x + 1, resteY + 1);
    coin(N - 1, N - 1, x + cote - 1, y + cote - 1, resteX + 1, resteY + 1);
    ctx.drawImage(source, x, y, cote, cote);
    return { x, y, cote };
  }

  /* Le contour d'un carré arrondi, à la manière des icônes de téléphone. */
  function cheminCarreArrondi(ctx, taille) {
    const r = taille * 0.2237;
    ctx.beginPath();
    ctx.moveTo(r, 0);
    ctx.arcTo(taille, 0, taille, taille, r);
    ctx.arcTo(taille, taille, 0, taille, r);
    ctx.arcTo(0, taille, 0, 0, r);
    ctx.arcTo(0, 0, taille, 0, r);
    ctx.closePath();
  }

  /* Pastille « réglages » de l'application admin : un disque bleu
     nuit cerné de blanc, avec la roue dentée. Elle se pose en bas à
     droite. Sur une tuile carrée elle va dans l'angle ; sous un masque
     rond, elle se pose tangente à l'intérieur de la zone sûre, sans
     quoi le téléphone lui couperait la moitié.
     @param rayonSur rayon utile de la tuile, en fraction du côté
                     (null : tuile carrée, l'angle est libre) */
  function pastilleAdmin(ctx, taille, pose, rayonSur) {
    let rExterieur;
    let cx;
    if (rayonSur === null) {
      rExterieur = taille * 0.175;
      cx = taille * 0.795;
    } else {
      const motifLarge = pose.cote * (MOTIF.x1 - MOTIF.x0);
      rExterieur = Math.min(motifLarge * 0.25, rayonSur * taille * 0.52);
      cx = taille / 2 + Math.max(0, rayonSur * taille - rExterieur) / Math.SQRT2;
    }
    const r = rExterieur * 0.855;
    const cy = cx;
    ctx.save();
    ctx.beginPath();
    ctx.arc(cx, cy, rExterieur, 0, Math.PI * 2);
    ctx.fillStyle = "#FFFFFF";
    ctx.fill();
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.fillStyle = "#001A6E";
    ctx.fill();

    /* Roue dentée : sommets et creux courbes, sinon le glyphe se lit
       « étoile ». Une dent = un arc large dehors, un arc étroit dedans. */
    const dents = 7;
    const rExt = r * 0.78;
    const rInt = r * 0.56;
    const pas = (Math.PI * 2) / dents;
    const largeurDent = pas * 0.52;
    ctx.beginPath();
    for (let k = 0; k < dents; k++) {
      const centre = k * pas - Math.PI / 2;
      ctx.arc(cx, cy, rExt, centre - largeurDent / 2, centre + largeurDent / 2);
      ctx.arc(cx, cy, rInt, centre + largeurDent / 2, centre + pas - largeurDent / 2);
    }
    ctx.closePath();
    ctx.fillStyle = "#FFFFFF";
    ctx.fill();
    ctx.beginPath();
    ctx.arc(cx, cy, r * 0.27, 0, Math.PI * 2);
    ctx.fillStyle = "#001A6E";
    ctx.fill();
    ctx.restore();
  }

  const sorties = {};
  for (const [nom, taille, forme, admin] of demandes) {
    const t = document.createElement("canvas");
    t.width = taille;
    t.height = taille;
    const ctx = t.getContext("2d");
    ctx.imageSmoothingQuality = "high";

    /* Pour chaque forme : l'échelle de l'œuvre, et le rayon utile de
       la tuile — ce que le masque du téléphone laisse voir. */
    let pose;
    let rayonSur;
    if (forme === "carre-arrondi") {
      ctx.save();
      cheminCarreArrondi(ctx, taille);
      ctx.clip();
      pose = poser(ctx, taille, 1);
      ctx.restore();
      rayonSur = null;
    } else if (forme === "rond") {
      ctx.save();
      ctx.beginPath();
      ctx.arc(taille / 2, taille / 2, taille / 2, 0, Math.PI * 2);
      ctx.clip();
      pose = poser(ctx, taille, 0.8);
      ctx.restore();
      rayonSur = 0.47;
    } else if (forme === "maskable") {
      /* Zone sûre PWA : disque de 80 % du côté. */
      pose = poser(ctx, taille, 0.84);
      rayonSur = 0.4;
    } else if (forme === "adaptatif") {
      /* Zone sûre Android : le motif doit tenir dans le disque de 72/108. */
      pose = poser(ctx, taille, 0.72);
      rayonSur = 0.333;
    } else {
      pose = poser(ctx, taille, 1);
      rayonSur = null;
    }
    if (admin) pastilleAdmin(ctx, taille, pose, rayonSur);
    sorties[nom] = t.toDataURL("image/png");
  }
  return sorties;
}

(async () => {
  if (!fs.existsSync(SOURCE)) {
    console.error("Œuvre introuvable : " + SOURCE);
    process.exit(1);
  }
  const b64 = fs.readFileSync(SOURCE).toString("base64");

  const demandes = [];
  for (const app of ["client", "admin"]) {
    const admin = app === "admin";
    for (const [nom, taille, forme] of CIBLES_PWA) demandes.push([app + "|pwa|" + nom, taille, forme, admin]);
    for (const [densite, classique, adaptatif] of DENSITES) {
      demandes.push([app + "|" + densite + "|ic_launcher.png", classique, "carre-arrondi", admin]);
      demandes.push([app + "|" + densite + "|ic_launcher_round.png", classique, "rond", admin]);
      demandes.push([app + "|" + densite + "|ic_launcher_fond.png", adaptatif, "adaptatif", admin]);
    }
  }

  const nav = await chromium.launch();
  const page = await nav.newPage();
  const sorties = await page.evaluate(atelier, [b64, MOTIF, demandes]);
  await nav.close();

  let ecrits = 0;
  for (const [cle, url] of Object.entries(sorties)) {
    const [app, dossier, nom] = cle.split("|");
    const cible =
      dossier === "pwa"
        ? path.join(RACINE, app, "icons", nom)
        : path.join(RACINE, "android", "app", "src", app, "res", dossier, nom);
    fs.mkdirSync(path.dirname(cible), { recursive: true });
    fs.writeFileSync(cible, Buffer.from(url.split(",")[1], "base64"));
    ecrits++;
  }

  /* Premier plan adaptatif : entièrement transparent. L'œuvre tient
     dans le calque de fond, motif déjà centré dans la zone sûre. */
  const vide = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
    "base64"
  );
  for (const app of ["client", "admin"]) {
    for (const [densite] of DENSITES) {
      fs.writeFileSync(
        path.join(RACINE, "android", "app", "src", app, "res", densite, "ic_launcher_premier_plan.png"),
        vide
      );
      ecrits++;
    }
  }

  console.log(ecrits + " icônes écrites depuis " + path.basename(SOURCE) + ".");
})();
