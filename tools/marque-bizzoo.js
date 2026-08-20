/* =========================================================
   La marque BIZZOO redessinée à plat.

   Pourquoi redessiner : dans l'œuvre d'origine, le B n'a pas
   d'intérieur à lui. Sa boucle est fermée par le sac, et le
   bleu foncé qu'on y voit EST le corps du sac dans l'ombre —
   pas un fond. Impossible d'y mettre du blanc sans effacer le
   sac. Redessinée, la marque a de vraies contre-formes : le
   blanc traverse le B.

   Le dessin tient dans un carré de 100 × 100. Il est rendu
   par le contexte 2D d'un canvas (Chromium), le même que
   celui des icônes.

   Ordre des plans, du fond vers l'avant :
     traits de vitesse · anse · sac · B · chariot
   Le B passe devant le sac, comme dans l'œuvre.
   ========================================================= */

/* Les couleurs de la charte, relevées sur l'œuvre. */
const COULEURS = {
  bleu: "#0B5CF5",
  bleuClair: "#2E7BFF",
  bleuProfond: "#0132A8",
  bleuNuit: "#001450",
  ciel: "#12A5FD",
  orange: "#F96302",
  orangeVif: "#FF7A16",
  ambre: "#FFA808",
  blanc: "#FFFFFF",
};

/**
 * Dessine la marque dans un carré de `taille`, coin haut-gauche en
 * (dx, dy). Rien d'autre n'est touché : le fond est posé par l'appelant.
 */
function dessinerMarque(ctx, dx, dy, taille) {
  const u = taille / 100;                     // une unité du dessin
  const X = (v) => dx + v * u;
  const Y = (v) => dy + v * u;
  const U = (v) => v * u;

  const barre = (x1, x2, y, epaisseur, couleur) => {
    ctx.fillStyle = couleur;
    ctx.beginPath();
    ctx.roundRect(X(x1), Y(y - epaisseur / 2), U(x2 - x1), U(epaisseur), U(epaisseur / 2));
    ctx.fill();
  };
  const disque = (cx, cy, r, couleur) => {
    ctx.fillStyle = couleur;
    ctx.beginPath();
    ctx.arc(X(cx), Y(cy), U(r), 0, Math.PI * 2);
    ctx.fill();
  };

  /* ---------- Les traits de vitesse ----------
     Trois barres et deux points : la marque avance. */
  barre(11, 27, 46, 6, COULEURS.ciel);
  barre(5, 24, 56, 6, COULEURS.bleu);
  barre(13, 26, 66, 6, COULEURS.orange);
  disque(6.5, 46, 3, COULEURS.ciel);
  disque(8, 66, 3, COULEURS.ambre);

  /* ---------- L'anse ----------
     Une arche ambrée, posée avant le sac : celui-ci vient ensuite en
     cacher les deux bouts, sinon l'ensemble se lit « cadenas ». */
  ctx.strokeStyle = COULEURS.ambre;
  ctx.lineWidth = U(6.5);
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.arc(X(42), Y(36), U(12), Math.PI, 2 * Math.PI);
  ctx.stroke();

  /* ---------- Le sac ----------
     Un corps bleu aux coins arrondis, et un rabat plus clair en haut
     qui lui donne du relief sans dégradé. */
  ctx.fillStyle = COULEURS.bleu;
  ctx.beginPath();
  ctx.roundRect(X(26), Y(35), U(34), U(51), U(7.5));
  ctx.fill();
  ctx.save();
  ctx.beginPath();
  ctx.roundRect(X(26), Y(35), U(34), U(51), U(7.5));
  ctx.clip();
  ctx.fillStyle = COULEURS.bleuClair;
  ctx.beginPath();
  ctx.moveTo(X(26), Y(35));
  ctx.lineTo(X(60), Y(35));
  ctx.lineTo(X(60), Y(45));
  ctx.lineTo(X(26), Y(48));
  ctx.closePath();
  ctx.fill();
  ctx.restore();

  /* ---------- Le chariot ----------
     Posé sur le corps bleu du sac, en blanc : il se détache là, et
     nulle part ailleurs. C'est pour cela qu'il ne va pas dans le B,
     dont les contre-formes doivent rester vides. */
  ctx.save();
  ctx.strokeStyle = COULEURS.blanc;
  ctx.fillStyle = COULEURS.blanc;
  ctx.lineWidth = U(3);
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.beginPath();
  ctx.moveTo(X(29), Y(56));
  ctx.lineTo(X(32.5), Y(56));
  ctx.lineTo(X(35.5), Y(70));
  ctx.lineTo(X(49), Y(70));
  ctx.stroke();
  ctx.beginPath();
  ctx.moveTo(X(33), Y(60));
  ctx.lineTo(X(52), Y(60));
  ctx.lineTo(X(50), Y(67.5));
  ctx.lineTo(X(34.6), Y(67.5));
  ctx.closePath();
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(X(38), Y(76), U(2.9), 0, Math.PI * 2);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(X(47), Y(76), U(2.9), 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();

  /* ---------- Le B ----------
     Un montant droit et deux panses en D, comme une vraie lettre. Les
     contre-formes sont PERCÉES : le fond blanc traverse la lettre —
     c'est tout l'objet de ce redessin. Le B passe devant le sac, comme
     dans l'œuvre d'origine. */
  ctx.fillStyle = COULEURS.orange;
  ctx.beginPath();
  ctx.roundRect(X(55), Y(24), U(10), U(62), [U(5), U(2), U(2), U(5)]);
  ctx.fill();
  ctx.beginPath();
  ctx.roundRect(X(59), Y(24), U(21), U(30), [U(3), U(15), U(15), U(3)]);
  ctx.fill();
  ctx.fillStyle = COULEURS.orangeVif;
  ctx.beginPath();
  ctx.roundRect(X(59), Y(52), U(25), U(34), [U(3), U(17), U(17), U(3)]);
  ctx.fill();
  /* Les trous de la lettre. */
  ctx.save();
  ctx.globalCompositeOperation = "destination-out";
  ctx.beginPath();
  ctx.roundRect(X(65.5), Y(31), U(8), U(16), [U(2), U(8), U(8), U(2)]);
  ctx.fill();
  ctx.beginPath();
  ctx.roundRect(X(65.5), Y(59.5), U(11), U(20), [U(2.5), U(10), U(10), U(2.5)]);
  ctx.fill();
  ctx.restore();
}

if (typeof module !== "undefined") module.exports = { dessinerMarque, COULEURS };
