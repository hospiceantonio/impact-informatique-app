/* =========================================================
   Fabrique les icônes des deux applications à partir de
   l'œuvre officielle BIZZOO (tools/bizzoo-icone.png) : la
   tuile bleue en dégradé, le B blanc qui dessine un chariot,
   et ses deux roues orange.

   L'ŒUVRE EST UNE TUILE À COINS ARRONDIS : c'est l'icône partout
   où elle reste carrée (PWA, Android d'avant la version 8). Trois
   usages demandent autre chose :

   - l'icône de l'iPhone et l'icône « maskable » : un carré
     PLEIN, que le téléphone arrondit lui-même — le dégradé doit
     aller jusque dans les coins ;
   - l'icône ronde d'Android : le même carré plein, découpé en
     disque ;
   - l'icône ADAPTATIVE d'Android : deux calques — le dégradé
     derrière, le B devant — que le téléphone découpe à sa forme
     (rond, goutte, carré arrondi…) et fait glisser l'un sur
     l'autre.

   On sépare donc l'œuvre en deux, sans rien redessiner :

   - le FOND est un dégradé linéaire. On le MESURE sur l'œuvre
     (moindres carrés sur les pixels bleus) : un plan par couleur,
     qui se prolonge au-delà de la tuile, dans les coins ;
   - le MOTIF : chaque pixel est lu comme un mélange du fond et
     d'une couleur pure — le blanc du B, l'orange de sa roue (un
     dégradé propre à chaque roue, mesuré lui aussi) —, et on en
     déduit son opacité. Le B garde ses bords adoucis.

   L'œuvre nous arrive compressée avec perte (WebP) : autour du B
   et des roues, un liseré délavé de 1 à 2 px. On lit donc l'opacité
   dans la luminance, que ce format garde intacte, et toutes les
   formes — la tuile carrée comprise — sont recomposées depuis les
   deux calques : le liseré disparaît, et elles se ressemblent
   toutes au pixel près.

   Le script vérifie ce qu'il fait : il recompose l'œuvre à partir
   des deux calques et mesure l'écart, il vérifie que le motif
   tient dans la zone que chaque téléphone laisse voir, et que la
   pastille de l'admin ne mord ni sur le B ni sur les roues.

   L'application admin reçoit la même icône, marquée d'une
   pastille « réglages » : les deux applications vivent sur le
   même téléphone, on doit les distinguer d'un coup d'œil. Elle
   se pose dans le coin bas-gauche, le seul que le B laisse libre.

   Enfin, la petite icône de la barre de notifications : la
   silhouette du B et de ses roues, tracée depuis la même œuvre
   (Android n'en garde que la forme, en blanc).

   Dépendance : Chromium, piloté par Playwright — il décode l'image
   et rééchantillonne proprement.
   Usage : node tools/make-icons.js
           (PLAYWRIGHT=<chemin de playwright-core> et CHROMIUM=<exécutable>
            si Playwright n'est pas installé globalement, comme pour les bancs)
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
const SOURCE = path.join(__dirname, "bizzoo-icone.png");

/* ---------- Les zones que les téléphones laissent voir ----------
   Tout est exprimé en fraction de la TUILE d'origine (de 0 à 1).

   La zone sûre d'une forme découpée est un disque : ce qui en sort
   peut disparaître sous le masque. On y fait tenir le motif ET la
   pastille de l'admin : un disque de 0,458 du côté de la tuile,
   centré. Le motif en occupe 0,393 (mesuré par le script). */
const ZONE_SURE_TUILE = 0.458;

/* L'icône adaptative : le calque fait 108 dp, le téléphone en montre
   72 au centre, et garantit un disque de 66 dp. La tuile est posée
   sur les 72 dp visibles — le dégradé et le motif y retombent comme
   sur l'œuvre —, et sa zone sûre tombe sur le disque de 66 dp. */
const ECHELLE_ADAPTATIVE = 72 / 108;
/* L'icône « maskable » : sa zone sûre est un disque de 40 % du côté. */
const ECHELLE_MASKABLE = 0.4 / ZONE_SURE_TUILE;

/* ---------- La pastille « réglages » de l'admin ----------
   Le coin bas-gauche est le seul que le B laisse libre. Sa taille et
   sa place changent avec ce que la forme découpe :
   - coin : la tuile entière (PWA, iPhone, Android classique) ;
   - rond : l'icône ronde d'Android, découpée en disque de 0,5 ;
   - sur  : la zone sûre des icônes adaptative et maskable. */
const PASTILLE = {
  coin: { x: 0.19, y: 0.81, r: 0.14 },
  rond: { x: 0.234, y: 0.766, r: 0.10 },
  sur: { x: 0.24, y: 0.76, r: 0.09 },
};
/* L'air minimal entre la pastille et le motif, en fraction de la tuile. */
const AIR_PASTILLE = 0.012;

/* L'écart de luminance toléré entre l'œuvre et sa recomposition, en
   niveaux de 0 à 255 : en moyenne, et au pire pixel hors des bords du
   motif. L'œuvre actuelle donne 0,34 et 9 (ce pire-là au ras du bord
   de la tuile, où la compression bave un peu). Au-delà, les deux
   calques ne rendent pas l'œuvre — une ombre, un reflet, un dessin
   d'une autre sorte — : le script s'arrête plutôt que de livrer des
   icônes infidèles. */
const RECOMPOSITION = { moyen: 1, max: 16 };

/* Icônes PWA. */
const CIBLES_PWA = [
  ["icon-192.png", 192, "tuile"],
  ["icon-512.png", 512, "tuile"],
  ["icon-maskable-512.png", 512, "maskable"],
  ["apple-touch-icon.png", 180, "plein"],
];

/* Android : côté de l'icône classique (48 dp) et des calques adaptatifs (108 dp). */
const DENSITES = [
  ["mipmap-mdpi", 48, 108],
  ["mipmap-hdpi", 72, 162],
  ["mipmap-xhdpi", 96, 216],
  ["mipmap-xxhdpi", 144, 324],
  ["mipmap-xxxhdpi", 192, 432],
];

/* Ce code s'exécute dans Chromium : il décode l'œuvre, la sépare en
   deux calques, vérifie, puis dessine chaque variante demandée. */
async function atelier([b64, R, demandes]) {
  const img = new Image();
  img.src = "data:image/png;base64," + b64;
  await img.decode();

  const N = img.width;
  const toile = (w, h) => {
    const c = document.createElement("canvas");
    c.width = w;
    c.height = h || w;
    return c;
  };
  const oeuvre = toile(N);
  const octx = oeuvre.getContext("2d");
  octx.drawImage(img, 0, 0);
  const src = octx.getImageData(0, 0, N, N).data;
  const bilan = {};

  /* ---------- 1. Le fond : un plan par couleur ----------
     c(u, v) = a + b·u + c·v, u et v de 0 à 1 sur la tuile. Deux
     passes : la seconde écarte les pixels que la première explique
     mal — les bords adoucis du B, qui ne sont pas du fond. */
  function resoudre(S, T) {
    const M = S.map((l, i) => l.concat([T[i]]));
    for (let i = 0; i < 3; i++) {
      let p = i;
      for (let k = i + 1; k < 3; k++) if (Math.abs(M[k][i]) > Math.abs(M[p][i])) p = k;
      [M[i], M[p]] = [M[p], M[i]];
      for (let k = 0; k < 3; k++) {
        if (k === i) continue;
        const f = M[k][i] / M[i][i];
        for (let j = 0; j < 4; j++) M[k][j] -= f * M[i][j];
      }
    }
    return [0, 1, 2].map((i) => M[i][3] / M[i][i]);
  }
  function ajuster(garder) {
    const S = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
    const T = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
    let n = 0;
    for (let y = 0; y < N; y += 2) {
      for (let x = 0; x < N; x += 2) {
        const i = (y * N + x) * 4;
        if (src[i + 3] < 255) continue;
        if (!(src[i + 2] > src[i] + 60 && src[i + 2] > src[i + 1] + 40)) continue;
        if (!garder(x, y, i)) continue;
        const v = [1, x / N, y / N];
        for (let a = 0; a < 3; a++) {
          for (let b = 0; b < 3; b++) S[a][b] += v[a] * v[b];
          for (let c = 0; c < 3; c++) T[c][a] += v[a] * src[i + c];
        }
        n++;
      }
    }
    return { coefs: [0, 1, 2].map((c) => resoudre(S, T[c])), n };
  }
  const plan = (coefs, u, v) => coefs.map((k) => k[0] + k[1] * u + k[2] * v);
  let fond = ajuster(() => true);
  const premier = fond.coefs;
  fond = ajuster((x, y, i) => {
    const p = plan(premier, x / N, y / N);
    return Math.max(Math.abs(p[0] - src[i]), Math.abs(p[1] - src[i + 1]),
      Math.abs(p[2] - src[i + 2])) <= 6;
  });
  const FOND = fond.coefs;
  const couleurFond = (u, v) => plan(FOND, u, v).map((c) => Math.max(0, Math.min(255, c)));
  bilan.fond = {
    pixels: fond.n,
    haut_gauche: couleurFond(0, 0).map(Math.round),
    bas_droite: couleurFond(1, 1).map(Math.round),
  };

  /* ---------- 2. Les roues : deux disques orange ---------- */
  const roues = [];
  for (const cote of [0, 1]) {
    let sx = 0, sy = 0, n = 0;
    for (let y = 0; y < N; y++) {
      for (let x = cote ? N >> 1 : 0; x < (cote ? N : N >> 1); x++) {
        const i = (y * N + x) * 4;
        if (src[i + 3] === 255 && src[i] > 200 && src[i + 1] > 60 && src[i + 1] < 200 && src[i + 2] < 90) {
          sx += x; sy += y; n++;
        }
      }
    }
    if (n) roues.push({ x: sx / n, y: sy / n, r: Math.sqrt(n / Math.PI) + 0.5 });
  }
  /* L'orange de chaque roue est un dégradé qui lui est propre (plus
     clair en haut à droite) : un plan par roue, mesuré en son cœur,
     autour de son centre. */
  for (const w of roues) {
    const S = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
    const T = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
    for (let y = Math.floor(w.y - w.r); y <= w.y + w.r; y++) {
      for (let x = Math.floor(w.x - w.r); x <= w.x + w.r; x++) {
        if (Math.hypot(x - w.x, y - w.y) > w.r * 0.8) continue;
        const i = (y * N + x) * 4;
        const v = [1, (x - w.x) / w.r, (y - w.y) / w.r];
        for (let a = 0; a < 3; a++) {
          for (let b = 0; b < 3; b++) S[a][b] += v[a] * v[b];
          for (let c = 0; c < 3; c++) T[c][a] += v[a] * src[i + c];
        }
      }
    }
    w.orange = [0, 1, 2].map((c) => resoudre(S, T[c]));
  }
  const orangeDe = (w, x, y) =>
    plan(w.orange, (x - w.x) / w.r, (y - w.y) / w.r).map((c) => Math.max(0, Math.min(255, c)));
  bilan.roues = roues.map((w) => ({
    x: Math.round(w.x), y: Math.round(w.y), r: Math.round(w.r),
    orange_au_centre: w.orange.map((k) => Math.round(k[0])),
  }));

  /* ---------- 3. Le motif : le mélange démêlé ----------
     Un pixel p = α·pur + (1 − α)·fond. Le fond est connu (le plan), la
     couleur pure aussi (le blanc du B, l'orange de sa roue) : reste α.
     On le lit dans la LUMINANCE. L'œuvre est un WebP compressé avec
     perte, qui garde la luminance à pleine résolution mais la couleur à
     demi-résolution : la couleur déborde des bords en un liseré délavé
     de 1 à 2 px, la luminance, elle, dit où passe le bord. À GRAIN
     niveaux près — le grain de la compression —, le fond est du fond et
     le motif du motif. */
  const luminance = (c) => 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2];
  const GRAIN = 4;
  const motif = toile(N);
  const mctx = motif.getContext("2d");
  const md = mctx.createImageData(N, N);
  const alpha = new Float32Array(N * N);
  const estRoue = new Uint8Array(N * N);
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      const k = y * N + x;
      const i = k * 4;
      if (src[i + 3] < 250) continue;          // hors de la tuile, ou son bord adouci
      const bg = couleurFond(x / N, y / N);
      const roue = roues.find((w) => Math.hypot(x - w.x, y - w.y) <= w.r + 3);
      const pur = roue ? orangeDe(roue, x, y) : [255, 255, 255];
      const lf = luminance(bg);
      const ecart = luminance(pur) - lf;
      let a = (luminance([src[i], src[i + 1], src[i + 2]]) - lf) / ecart;
      const marge = GRAIN / Math.abs(ecart);
      a = a < marge ? 0 : a > 1 - marge ? 1 : a;
      if (!a) continue;
      md.data[i] = pur[0];
      md.data[i + 1] = pur[1];
      md.data[i + 2] = pur[2];
      md.data[i + 3] = Math.round(a * 255);
      alpha[k] = a;
      if (roue) estRoue[k] = 1;
    }
  }
  mctx.putImageData(md, 0, 0);

  /* ---------- 4. Vérifications ---------- */
  /* a. Fond + motif redonnent l'œuvre, en luminance. Au ras des bords
     du motif (BORD px de part et d'autre), la compression a laissé des
     ondes que la séparation efface : l'écart y est mesuré, sans plus.
     Partout ailleurs, il doit rester sous RECOMPOSITION.max : une ombre
     ou un reflet que les deux calques ne savent pas rendre y ferait des
     bandes entières. */
  const BORD = 3;
  const presDUnBord = (x, y) => {
    let dedans = false, dehors = false;
    for (let dy = -BORD; dy <= BORD; dy++) {
      for (let dx = -BORD; dx <= BORD; dx++) {
        const xx = x + dx, yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= N || yy >= N) continue;
        if (alpha[yy * N + xx] >= 0.5) dedans = true; else dehors = true;
        if (dedans && dehors) return true;
      }
    }
    return false;
  };
  let somme = 0, sommeCouleur = 0, n = 0, pireAuxBords = 0, pireAilleurs = 0;
  for (let y = 0; y < N; y += 2) {
    for (let x = 0; x < N; x += 2) {
      const k = y * N + x;
      const i = k * 4;
      if (src[i + 3] < 255) continue;
      const bg = couleurFond(x / N, y / N);
      const a = md.data[i + 3] / 255;
      const r = [0, 1, 2].map((c) => a * md.data[i + c] + (1 - a) * bg[c]);
      const e = Math.abs(luminance(r) - luminance([src[i], src[i + 1], src[i + 2]]));
      somme += e; n++;
      sommeCouleur += Math.max(...[0, 1, 2].map((c) => Math.abs(r[c] - src[i + c])));
      if (presDUnBord(x, y)) pireAuxBords = Math.max(pireAuxBords, e);
      else pireAilleurs = Math.max(pireAilleurs, e);
    }
  }
  bilan.recomposition = {
    luminance_ecart_moyen: +(somme / n).toFixed(2),
    luminance_ecart_max_hors_bords: Math.round(pireAilleurs),
    luminance_ecart_max_aux_bords: Math.round(pireAuxBords),
    couleur_ecart_moyen: +(sommeCouleur / n).toFixed(2),
  };
  if (somme / n > R.RECOMPOSITION.moyen || pireAilleurs > R.RECOMPOSITION.max) {
    throw new Error("Fond + motif ne redonnent pas l'œuvre : " + JSON.stringify(bilan.recomposition));
  }

  /* b. Le motif tient-il dans la zone sûre ? */
  let rayonMotif = 0;
  const pointsMotif = [];
  for (let y = 0; y < N; y += 2) {
    for (let x = 0; x < N; x += 2) {
      if (alpha[y * N + x] < 0.05) continue;
      rayonMotif = Math.max(rayonMotif, Math.hypot(x / N - 0.5, y / N - 0.5));
      pointsMotif.push([x / N, y / N]);
    }
  }
  bilan.rayon_motif = +rayonMotif.toFixed(3);
  if (rayonMotif > R.ZONE_SURE_TUILE) {
    throw new Error("Le motif déborde de la zone sûre : " + rayonMotif.toFixed(3));
  }

  /* c. La pastille : dans sa forme, et à distance du motif. */
  let rayonCoin = 0;
  while (rayonCoin < N && src[(rayonCoin * N) * 4 + 3] < 128) rayonCoin++;
  rayonCoin /= N;
  bilan.arrondi_tuile = +rayonCoin.toFixed(3);
  bilan.pastille = {};
  for (const [nom, p] of Object.entries(R.PASTILLE)) {
    let air = Infinity;
    for (const [u, v] of pointsMotif) air = Math.min(air, Math.hypot(u - p.x, v - p.y) - p.r);
    const d = Math.hypot(p.x - 0.5, p.y - 0.5);
    let dedans;
    if (nom === "coin") {
      /* Tout le tour de la pastille doit tomber dans la tuile, coins
         arrondis compris : on en fait le tour, point par point. */
      const dansTuile = (u, v) => {
        const qx = Math.max(rayonCoin - u, u - (1 - rayonCoin), 0);
        const qy = Math.max(rayonCoin - v, v - (1 - rayonCoin), 0);
        return u >= 0 && u <= 1 && v >= 0 && v <= 1 && Math.hypot(qx, qy) <= rayonCoin;
      };
      dedans = true;
      for (let k = 0; k < 72; k++) {
        const a = (k / 72) * Math.PI * 2;
        if (!dansTuile(p.x + p.r * Math.cos(a), p.y + p.r * Math.sin(a))) dedans = false;
      }
    } else if (nom === "rond") {
      dedans = d + p.r <= 0.48;
    } else {
      dedans = d + p.r <= R.ZONE_SURE_TUILE + 1e-6;
    }
    bilan.pastille[nom] = { air: +air.toFixed(3), dedans };
    if (air < R.AIR_PASTILLE || !dedans) {
      throw new Error("Pastille « " + nom + " » mal placée : air " + air.toFixed(3) +
        (dedans ? "" : ", hors de sa forme"));
    }
  }

  /* ---------- 5. Dessiner ---------- */
  /* Réduction par moitiés successives : d'un seul coup, 1 280 → 48
     crénelle les bords du B. */
  function reduire(c0, taille) {
    let cur = c0;
    while (cur.width / 2 >= taille) {
      const n2 = toile(Math.round(cur.width / 2));
      const x = n2.getContext("2d");
      x.imageSmoothingEnabled = true;
      x.imageSmoothingQuality = "high";
      x.drawImage(cur, 0, 0, n2.width, n2.height);
      cur = n2;
    }
    const fin = toile(taille);
    const x = fin.getContext("2d");
    x.imageSmoothingEnabled = true;
    x.imageSmoothingQuality = "high";
    x.drawImage(cur, 0, 0, taille, taille);
    return fin;
  }

  /* Le fond, calculé pixel par pixel à la taille voulue : un dégradé
     n'a pas à être rééchantillonné. La tuile occupe T pixels au centre. */
  function peindreFond(ctx, taille, echelle) {
    const t = taille * echelle;
    const o = (taille - t) / 2;
    const d = ctx.createImageData(taille, taille);
    for (let y = 0; y < taille; y++) {
      for (let x = 0; x < taille; x++) {
        const c = couleurFond((x + 0.5 - o) / t, (y + 0.5 - o) / t);
        const i = (y * taille + x) * 4;
        d.data[i] = c[0];
        d.data[i + 1] = c[1];
        d.data[i + 2] = c[2];
        d.data[i + 3] = 255;
      }
    }
    ctx.putImageData(d, 0, 0);
  }

  function poserMotif(ctx, taille, echelle) {
    const t = Math.round(taille * echelle);
    const o = (taille - t) / 2;
    ctx.drawImage(reduire(motif, t), o, o);
  }

  /* Pastille « réglages » : un disque bleu nuit cerné de blanc, avec
     la roue dentée. Coordonnées en fraction de la tuile. */
  function pastilleAdmin(ctx, taille, echelle, p) {
    const t = taille * echelle;
    const o = (taille - t) / 2;
    const cx = o + p.x * t;
    const cy = o + p.y * t;
    const rExterieur = p.r * t;
    const r = rExterieur * 0.855;
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
    const t = toile(taille);
    const ctx = t.getContext("2d");
    let echelle = 1;
    let pastille = R.PASTILLE.coin;
    let avecPastille = admin;
    if (forme === "tuile") {
      /* L'œuvre recomposée depuis ses deux calques — le liseré de la
         compression en moins, comme sur toutes les autres formes —,
         découpée selon les coins arrondis de l'œuvre. */
      peindreFond(ctx, taille, 1);
      poserMotif(ctx, taille, 1);
      ctx.globalCompositeOperation = "destination-in";
      ctx.drawImage(reduire(oeuvre, taille), 0, 0);
      ctx.globalCompositeOperation = "source-over";
    } else if (forme === "plein") {
      peindreFond(ctx, taille, 1);
      poserMotif(ctx, taille, 1);
    } else if (forme === "rond") {
      peindreFond(ctx, taille, 1);
      poserMotif(ctx, taille, 1);
      ctx.globalCompositeOperation = "destination-in";
      ctx.beginPath();
      ctx.arc(taille / 2, taille / 2, taille / 2, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalCompositeOperation = "source-over";
      pastille = R.PASTILLE.rond;
    } else if (forme === "maskable") {
      echelle = R.ECHELLE_MASKABLE;
      peindreFond(ctx, taille, echelle);
      poserMotif(ctx, taille, echelle);
      pastille = R.PASTILLE.sur;
    } else if (forme === "premier-plan") {
      echelle = R.ECHELLE_ADAPTATIVE;
      poserMotif(ctx, taille, echelle);
      pastille = R.PASTILLE.sur;
    } else if (forme === "fond") {
      echelle = R.ECHELLE_ADAPTATIVE;
      peindreFond(ctx, taille, echelle);
      avecPastille = false;                      // la pastille va au premier plan
    }
    if (avecPastille) pastilleAdmin(ctx, taille, echelle, pastille);
    sorties[nom] = t.toDataURL("image/png");
  }

  /* ---------- 6. La silhouette de la barre de notifications ----------
     Le B tracé en contour (marching squares sur l'opacité, puis
     simplifié), les roues en cercles exacts. Android n'en garde que la
     forme : les deux trous du B restent des trous (evenOdd). */
  const CELLULE = 4;
  let bx0 = N, by0 = N, bx1 = 0, by1 = 0;
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      if (alpha[y * N + x] < 0.05) continue;
      bx0 = Math.min(bx0, x); by0 = Math.min(by0, y);
      bx1 = Math.max(bx1, x); by1 = Math.max(by1, y);
    }
  }
  const gx0 = bx0 - 2 * CELLULE;
  const gy0 = by0 - 2 * CELLULE;
  const GW = Math.ceil((bx1 - gx0 + 2 * CELLULE) / CELLULE) + 1;
  const GH = Math.ceil((by1 - gy0 + 2 * CELLULE) / CELLULE) + 1;
  const champ = new Float32Array(GW * GH);
  for (let j = 0; j < GH; j++) {
    for (let i = 0; i < GW; i++) {
      let s = 0, c = 0;
      for (let dy = 0; dy < CELLULE; dy++) {
        for (let dx = 0; dx < CELLULE; dx++) {
          const x = gx0 + i * CELLULE + dx;
          const y = gy0 + j * CELLULE + dy;
          if (x < 0 || y < 0 || x >= N || y >= N) { c++; continue; }
          const k = y * N + x;
          s += estRoue[k] ? 0 : alpha[k];
          c++;
        }
      }
      champ[j * GW + i] = s / c;
    }
  }
  /* Marching squares : chaque segment relie deux arêtes de la grille. */
  const val = (i, j) => (i < 0 || j < 0 || i >= GW || j >= GH ? 0 : champ[j * GW + i]);
  const SEUIL = 0.5;
  const pointArete = (cle) => {
    const [t, a, b] = cle.split(":");
    const i = +a, j = +b;
    if (t === "h") {                        // entre (i, j) et (i + 1, j)
      const v0 = val(i, j), v1 = val(i + 1, j);
      return [i + (SEUIL - v0) / (v1 - v0), j];
    }
    const v0 = val(i, j), v1 = val(i, j + 1); // entre (i, j) et (i, j + 1)
    return [i, j + (SEUIL - v0) / (v1 - v0)];
  };
  const liens = new Map();
  const relier = (a, b) => {
    if (!liens.has(a)) liens.set(a, []);
    if (!liens.has(b)) liens.set(b, []);
    liens.get(a).push(b);
    liens.get(b).push(a);
  };
  for (let j = -1; j < GH; j++) {
    for (let i = -1; i < GW; i++) {
      const tl = val(i, j) >= SEUIL, tr = val(i + 1, j) >= SEUIL;
      const br = val(i + 1, j + 1) >= SEUIL, bl = val(i, j + 1) >= SEUIL;
      const cas = (tl ? 8 : 0) | (tr ? 4 : 0) | (br ? 2 : 0) | (bl ? 1 : 0);
      const H = "h:" + i + ":" + j, B = "h:" + i + ":" + (j + 1);
      const G = "v:" + i + ":" + j, D = "v:" + (i + 1) + ":" + j;
      const centre = (val(i, j) + val(i + 1, j) + val(i + 1, j + 1) + val(i, j + 1)) / 4 >= SEUIL;
      switch (cas) {
        case 1: case 14: relier(G, B); break;
        case 2: case 13: relier(B, D); break;
        case 3: case 12: relier(G, D); break;
        case 4: case 11: relier(H, D); break;
        case 6: case 9: relier(H, B); break;
        case 7: case 8: relier(G, H); break;
        case 5: if (centre) { relier(G, H); relier(B, D); } else { relier(G, B); relier(H, D); } break;
        case 10: if (centre) { relier(H, D); relier(G, B); } else { relier(G, H); relier(B, D); } break;
        default: break;
      }
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
      prec = cur;
      cur = suivants[0];
    }
    if (boucle.length > 8) boucles.push(boucle);
  }
  /* Douglas-Peucker, sur chaque boucle fermée. */
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
    return simplifier(pts.slice(0, loin + 1), eps).slice(0, -1)
      .concat(simplifier(pts.slice(loin), eps));
  }
  /* Le motif entier (B + roues) tient dans 20 × 20 au centre du carré
     de 24 : la marge de 2 dp que demande Android. */
  const hauteurMotif = (by1 - by0 + 1);
  const largeurMotif = (bx1 - bx0 + 1);
  const ech = 20 / Math.max(hauteurMotif, largeurMotif);
  const cxm = (bx0 + bx1 + 1) / 2, cym = (by0 + by1 + 1) / 2;
  const versVue = (X, Y) => [12 + (X - cxm) * ech, 12 + (Y - cym) * ech];
  const f = (v) => (Math.round(v * 100) / 100).toString();
  let chemin = "";
  let nbPoints = 0;
  for (const boucle of boucles) {
    /* On ferme la boucle pour la simplifier en deux moitiés. */
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
  for (const w of roues) {
    const [x, y] = versVue(w.x + 0.5, w.y + 0.5);
    const r = w.r * ech;
    chemin += "M" + f(x - r) + "," + f(y) + "a" + f(r) + "," + f(r) + " 0,1 0," + f(2 * r) + ",0" +
      "a" + f(r) + "," + f(r) + " 0,1 0," + f(-2 * r) + ",0Z ";
  }
  bilan.notification = { boucles: boucles.length, points: nbPoints };

  return { sorties, bilan, chemin: chemin.trim() };
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
      demandes.push([app + "|" + densite + "|ic_launcher.png", classique, "tuile", admin]);
      demandes.push([app + "|" + densite + "|ic_launcher_round.png", classique, "rond", admin]);
      demandes.push([app + "|" + densite + "|ic_launcher_premier_plan.png", adaptatif, "premier-plan", admin]);
      demandes.push([app + "|" + densite + "|ic_launcher_fond.png", adaptatif, "fond", admin]);
    }
  }

  const chromium = chargerChromium();
  const nav = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
  const page = await nav.newPage();
  const R = { ZONE_SURE_TUILE, ECHELLE_ADAPTATIVE, ECHELLE_MASKABLE, PASTILLE, AIR_PASTILLE, RECOMPOSITION };
  let resultat;
  try {
    resultat = await page.evaluate(atelier, [b64, R, demandes]);
  } finally {
    await nav.close();
  }
  const { sorties, bilan, chemin } = resultat;

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

  /* La silhouette de la barre de notifications, commune aux deux applications. */
  const notif = path.join(RACINE, "android", "app", "src", "main", "res", "drawable", "ic_notification.xml");
  fs.writeFileSync(notif,
    '<?xml version="1.0" encoding="utf-8"?>\n' +
    "<!-- Icône de la barre de notifications : le B de BIZZOO et ses deux\n" +
    "     roues. Android n'en garde que la silhouette, en blanc : les deux\n" +
    "     trous du B restent des trous (fillType evenOdd).\n" +
    "     Fichier produit par tools/make-icons.js depuis tools/bizzoo-icone.png :\n" +
    "     ne pas le retoucher à la main. -->\n" +
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

  console.log(JSON.stringify(bilan, null, 2));
  console.log(ecrits + " icônes écrites depuis " + path.basename(SOURCE) +
    ", et la silhouette des notifications.");
})().catch((err) => {
  console.error(err && err.message ? err.message : err);
  process.exit(1);
});
