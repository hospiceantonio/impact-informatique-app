/* =========================================================
   Fabrique les icônes des deux applications à partir de
   l'œuvre officielle BIZZOO (tools/bizzoo-icone.jpg) : le sac
   de courses qui dessine un B, le chariot blanc et les traits
   de vitesse.

   Le fond bleu de l'œuvre est RETIRÉ : sur le téléphone, la
   tuile bleue pleine écrasait tout. Il ne reste que le motif,
   posé sur blanc.

   Comment on détoure : on part des bords du carré et on avance
   tant que la couleur ne change presque pas. Le fond est un
   dégradé lisse — la propagation le suit sans peine ; le motif
   a des bords francs — elle s'y arrête. Le chariot blanc,
   enfermé au milieu du motif, est conservé : la propagation ne
   peut pas l'atteindre. (Un simple seuil de couleur ne
   marcherait pas : le sac est bleu, comme le fond.)

   Ce que le script produit, pour chaque application :
   - les icônes PWA (192, 512, maskable, apple-touch) ;
   - les icônes Android classiques et adaptatives, toutes
     densités.

   L'application admin reçoit le même motif, marqué d'une
   pastille « réglages » : les deux applications vivent sur le
   même téléphone, on doit les distinguer d'un coup d'œil.

   Dépendance : Chromium, piloté par Playwright — il décode le
   JPEG et rééchantillonne proprement.
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

/* Réglages du détourage, trouvés à l'œil sur l'œuvre :
   - tolerance : écart de couleur admis d'un pixel au suivant ;
     au-delà de 4, la propagation franchit le bord du sac ;
   - retrait   : part du côté rentrée pour effacer le liseré adouci
     du cadre (le faire par érosion creuserait aussi autour du
     chariot blanc, qui est un trou dans le masque) ;
   - frange    : pixels de bord grignotés, mélangés au bleu par le
     lissage — sans quoi le motif garde un halo sur blanc. */
const DETOURAGE = { tolerance: 4, retrait: 0.035, frange: 1 };

/* Le fond de la tuile : blanc franc. L'œuvre garde sa structure, on ne
   lui retire que son fond bleu. */
const FOND = "#FFFFFF";

/* Part du côté occupée par le motif, selon ce que le téléphone
   laisse voir. Sur une tuile carrée on peut aller large ; sous un
   masque rond, il faut que la DIAGONALE du motif tienne dans le
   disque. Le motif remplit largement : une pastille trop vide se
   perd sur l'écran d'accueil. */
const EMPRISE = { carre: 0.84, rond: 0.7, maskable: 0.7, adaptatif: 0.6 };
/* Repère : le calque adaptatif fait 108 dp mais le téléphone n'en
   montre que 72 — le motif à 0,60 occupe donc 90 % de ce qu'on voit.
   Au-delà, les traits de vitesse se font couper. */

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

/* Ce code s'exécute dans Chromium : il décode l'œuvre, détoure le
   motif, puis dessine chaque variante demandée. */
async function atelier([b64, DETOURAGE, EMPRISE, FOND, demandes]) {
  const img = new Image();
  img.src = "data:image/jpeg;base64," + b64;
  await img.decode();

  const N = img.width;
  const source = document.createElement("canvas");
  source.width = N;
  source.height = N;
  const sctx = source.getContext("2d");
  sctx.drawImage(img, 0, 0);
  const src = sctx.getImageData(0, 0, N, N).data;

  /* La tuile d'origine : pixels franchement colorés. Le blanc autour
     et son ombre grise n'en sont pas. */
  const dedans = new Uint8Array(N * N);
  let x0 = N;
  let y0 = N;
  let x1 = -1;
  let y1 = -1;
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      const i = (y * N + x) * 4;
      const mx = Math.max(src[i], src[i + 1], src[i + 2]);
      const mn = Math.min(src[i], src[i + 1], src[i + 2]);
      if (mx - mn > 45) {
        dedans[y * N + x] = 1;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }

  /* Propagation du fond depuis une couronne posée juste à l'intérieur
     du cadre. On compare chaque pixel à son VOISIN, pas au germe : le
     dégradé se suit ainsi de proche en proche, alors qu'un écart mesuré
     depuis le germe finirait par tout avaler. */
  const fond = new Uint8Array(N * N);
  const pile = [];
  const semer = (x, y) => {
    const k = y * N + x;
    if (!dedans[k] || fond[k]) return;
    fond[k] = 1;
    pile.push(k);
  };
  const marge = Math.round(N * 0.09);
  for (let x = x0; x <= x1; x++) {
    for (let d = 0; d < marge; d++) {
      if (y0 + d <= y1) semer(x, y0 + d);
      if (y1 - d >= y0) semer(x, y1 - d);
    }
  }
  for (let y = y0; y <= y1; y++) {
    for (let d = 0; d < marge; d++) {
      if (x0 + d <= x1) semer(x0 + d, y);
      if (x1 - d >= x0) semer(x1 - d, y);
    }
  }
  while (pile.length) {
    const k = pile.pop();
    const x = k % N;
    const y = (k - x) / N;
    const i = k * 4;
    const voisins = [[1, 0], [-1, 0], [0, 1], [0, -1]];
    for (const [dx, dy] of voisins) {
      const nx = x + dx;
      const ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= N || ny >= N) continue;
      const nk = ny * N + nx;
      if (fond[nk] || !dedans[nk]) continue;
      const j = nk * 4;
      const ecart = Math.max(
        Math.abs(src[i] - src[j]),
        Math.abs(src[i + 1] - src[j + 1]),
        Math.abs(src[i + 2] - src[j + 2])
      );
      if (ecart <= DETOURAGE.tolerance) {
        fond[nk] = 1;
        pile.push(nk);
      }
    }
  }

  /* Le liseré du cadre s'en va par géométrie : un carré arrondi rentré
     de quelques pour cent. */
  const cote = Math.max(x1 - x0, y1 - y0);
  const inset = cote * DETOURAGE.retrait;
  const bx0 = x0 + inset;
  const by0 = y0 + inset;
  const bx1 = x1 - inset;
  const by1 = y1 - inset;
  const rCadre = (bx1 - bx0) * 0.2237;
  const dansCadre = (x, y) => {
    if (x < bx0 || x > bx1 || y < by0 || y > by1) return false;
    const qx = Math.max(bx0 + rCadre - x, x - (bx1 - rCadre), 0);
    const qy = Math.max(by0 + rCadre - y, y - (by1 - rCadre), 0);
    return Math.hypot(qx, qy) <= rCadre;
  };

  let masque = new Uint8Array(N * N);
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      const k = y * N + x;
      masque[k] = !fond[k] && dansCadre(x, y) ? 1 : 0;
    }
  }
  for (let tour = 0; tour < DETOURAGE.frange; tour++) {
    const suivant = new Uint8Array(N * N);
    for (let y = 1; y < N - 1; y++) {
      for (let x = 1; x < N - 1; x++) {
        const k = y * N + x;
        if (masque[k] && masque[k - 1] && masque[k + 1] && masque[k - N] && masque[k + N]) {
          suivant[k] = 1;
        }
      }
    }
    masque = suivant;
  }

  /* Le motif, fond transparent, rogné au plus juste : c'est lui qu'on
     posera ensuite sur du blanc, à la taille voulue. */
  let mx0 = N;
  let my0 = N;
  let mx1 = -1;
  let my1 = -1;
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      if (!masque[y * N + x]) continue;
      if (x < mx0) mx0 = x;
      if (x > mx1) mx1 = x;
      if (y < my0) my0 = y;
      if (y > my1) my1 = y;
    }
  }
  const plein = document.createElement("canvas");
  plein.width = N;
  plein.height = N;
  const pctx = plein.getContext("2d");
  const im = pctx.createImageData(N, N);
  for (let k = 0; k < N * N; k++) {
    const i = k * 4;
    if (!masque[k]) continue;
    im.data[i] = src[i];
    im.data[i + 1] = src[i + 1];
    im.data[i + 2] = src[i + 2];
    im.data[i + 3] = 255;
  }
  pctx.putImageData(im, 0, 0);

  const largeurMotif = mx1 - mx0 + 1;
  const hauteurMotif = my1 - my0 + 1;
  const coteMotif = Math.max(largeurMotif, hauteurMotif);
  /* Carré autour du motif : il se posera ainsi sans se déformer. */
  const motif = document.createElement("canvas");
  motif.width = coteMotif;
  motif.height = coteMotif;
  motif.getContext("2d").drawImage(
    plein,
    mx0 - (coteMotif - largeurMotif) / 2,
    my0 - (coteMotif - hauteurMotif) / 2,
    coteMotif,
    coteMotif,
    0,
    0,
    coteMotif,
    coteMotif
  );

  /* Le motif centré sur du blanc, à l'emprise voulue. */
  function poser(ctx, taille, emprise) {
    ctx.fillStyle = FOND;
    ctx.fillRect(0, 0, taille, taille);
    return poserSansFond(ctx, taille, emprise);
  }

  /* Le motif seul, sans rien derrière. */
  function poserSansFond(ctx, taille, emprise) {
    const c = taille * emprise;
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(motif, (taille - c) / 2, (taille - c) / 2, c, c);
    return { cote: c };
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

  /* Pastille « réglages » de l'application admin : un disque bleu nuit
     cerné de blanc, avec la roue dentée. Sur une tuile carrée elle va
     dans l'angle ; sous un masque rond, elle se pose tangente à
     l'intérieur de la zone sûre, sans quoi le téléphone lui couperait
     la moitié.
     @param rayonSur rayon utile de la tuile, en fraction du côté
                     (null : tuile carrée, l'angle est libre) */
  function pastilleAdmin(ctx, taille, pose, rayonSur) {
    let rExterieur;
    let cx;
    if (rayonSur === null) {
      rExterieur = taille * 0.17;
      cx = taille * 0.79;
    } else {
      rExterieur = Math.min(pose.cote * 0.26, rayonSur * taille * 0.52);
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

    let pose;
    let rayonSur;
    if (forme === "carre-arrondi") {
      ctx.save();
      cheminCarreArrondi(ctx, taille);
      ctx.clip();
      pose = poser(ctx, taille, EMPRISE.carre);
      ctx.restore();
      rayonSur = null;
    } else if (forme === "rond") {
      ctx.save();
      ctx.beginPath();
      ctx.arc(taille / 2, taille / 2, taille / 2, 0, Math.PI * 2);
      ctx.clip();
      pose = poser(ctx, taille, EMPRISE.rond);
      ctx.restore();
      rayonSur = 0.47;
    } else if (forme === "maskable") {
      /* Zone sûre PWA : disque de 80 % du côté. */
      pose = poser(ctx, taille, EMPRISE.maskable);
      rayonSur = 0.4;
    } else if (forme === "premier-plan") {
      /* Le calque AVANT d'une icône adaptative : le motif seul, sur du
         vide. Le fond est une couleur à part (blanc), déclarée dans le
         XML. C'est la forme que les lanceurs attendent ; tout mettre
         dans le calque de fond, comme on le faisait, les pousse à
         repeindre la tuile à leur façon. */
      pose = poserSansFond(ctx, taille, EMPRISE.adaptatif);
      rayonSur = 0.333;
    } else {
      pose = poser(ctx, taille, EMPRISE.carre);
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
      demandes.push([app + "|" + densite + "|ic_launcher_premier_plan.png", adaptatif, "premier-plan", admin]);
    }
  }

  const nav = await chromium.launch();
  const page = await nav.newPage();
  const sorties = await page.evaluate(atelier, [b64, DETOURAGE, EMPRISE, FOND, demandes]);
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

  /* L'ancien calque de fond en image ne sert plus : le fond est une
     couleur, déclarée dans le XML de l'icône adaptative. */
  for (const app of ["client", "admin"]) {
    for (const [densite] of DENSITES) {
      const vieux = path.join(RACINE, "android", "app", "src", app, "res", densite, "ic_launcher_fond.png");
      if (fs.existsSync(vieux)) fs.unlinkSync(vieux);
    }
  }

  console.log(ecrits + " icônes écrites depuis " + path.basename(SOURCE) + " (motif détouré sur blanc).");
})();
