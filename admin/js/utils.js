/* =========================================================
   Utilitaires : textes, montants, dates, téléphone, photos.
   ========================================================= */
const Utils = (() => {

  const MOIS = ["janvier","février","mars","avril","mai","juin","juillet","août","septembre","octobre","novembre","décembre"];

  const pad = (n, len = 2) => String(n).padStart(len, "0");

  function uid(prefixe = "id") {
    return prefixe + "_" + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
  }

  function echapper(valeur) {
    return String(valeur === null || valeur === undefined ? "" : valeur)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  /* ---------- Montants ---------- */

  function fmtNombre(n) {
    const v = Math.round(Number(n) || 0);
    return String(Math.abs(v)).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  }

  function fmtMontant(n, devise) {
    const v = Math.round(Number(n) || 0);
    const signe = v < 0 ? "-" : "";
    return signe + fmtNombre(v) + (devise ? " " + devise : "");
  }

  /** Accepte "12 500", "12.500", "12,5" et renvoie un nombre. */
  function lireNombre(valeur) {
    if (typeof valeur === "number") return isFinite(valeur) ? valeur : 0;
    if (!valeur) return 0;
    let s = String(valeur).trim().replace(/\s/g, "");
    if (/^\d{1,3}(\.\d{3})+$/.test(s)) s = s.replace(/\./g, "");
    s = s.replace(",", ".").replace(/[^\d.-]/g, "");
    const n = parseFloat(s);
    return isFinite(n) ? n : 0;
  }

  /** "-12 %" entre ancien prix et prix actuel (null si pas de vraie remise). */
  function remisePourcent(ancienPrix, prix) {
    const a = Number(ancienPrix) || 0;
    const p = Number(prix) || 0;
    if (a <= 0 || p <= 0 || a <= p) return null;
    return Math.round(((a - p) / a) * 100);
  }

  /* ---------- Dates ---------- */

  function fmtDateHeure(horodatage) {
    if (!horodatage) return "—";
    const d = new Date(horodatage);
    if (isNaN(d)) return "—";
    return d.getDate() + " " + MOIS[d.getMonth()] + " " + d.getFullYear() +
      " à " + pad(d.getHours()) + ":" + pad(d.getMinutes());
  }

  function fmtDate(horodatage) {
    if (!horodatage) return "—";
    const d = new Date(horodatage);
    if (isNaN(d)) return "—";
    return d.getDate() + " " + MOIS[d.getMonth()] + " " + d.getFullYear();
  }

  /** Heure seule : « 14:32 » (dans l'historique, le jour est donné à part). */
  function fmtHeure(horodatage) {
    if (!horodatage) return "—";
    const d = new Date(horodatage);
    if (isNaN(d)) return "—";
    return pad(d.getHours()) + ":" + pad(d.getMinutes());
  }

  /* ---------- Téléphone & WhatsApp ---------- */

  /**
   * Numéro au format international sans "+" (ex. 2290197000000).
   * Le zéro de tête est conservé : les numéros béninois commencent par 01.
   */
  function normaliserTel(tel, indicatif) {
    let s = String(tel || "").trim();
    const international = s.startsWith("+") || s.startsWith("00");
    s = s.replace(/\D/g, "");
    if (s.startsWith("00")) s = s.slice(2);
    if (!s) return "";
    const ind = String(indicatif || "").replace(/\D/g, "");
    if (international) return s;
    if (ind && s.startsWith(ind) && s.length > ind.length + 5) return s;
    return ind ? ind + s : s;
  }

  function lienWhatsApp(tel, message, indicatif) {
    const num = normaliserTel(tel, indicatif);
    const base = num ? "https://wa.me/" + num : "https://wa.me/";
    return base + (message ? "?text=" + encodeURIComponent(message) : "");
  }

  /* ---------- Divers ---------- */

  /** Comparaison insensible aux accents et à la casse. */
  function sansAccent(s) {
    return String(s || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  }

  function tempo(fn, ms = 220) {
    let t;
    return function (...args) {
      clearTimeout(t);
      t = setTimeout(() => fn.apply(this, args), ms);
    };
  }

  function telecharger(nomFichier, contenu, type = "application/json") {
    /* Dans l'application Android, le téléphone enregistre le fichier
       dans Téléchargements via le pont natif. */
    if (typeof contenu === "string" && window.AndroidPont && window.AndroidPont.enregistrerFichier) {
      const base64 = btoa(unescape(encodeURIComponent(contenu)));
      window.AndroidPont.enregistrerFichier(nomFichier, base64, type);
      return;
    }
    const blob = contenu instanceof Blob ? contenu : new Blob([contenu], { type: type + ";charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = nomFichier;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
  }

  function tailleLisible(octets) {
    if (!octets) return "0 Ko";
    if (octets < 1024 * 1024) return Math.round(octets / 1024) + " Ko";
    return (octets / (1024 * 1024)).toFixed(1) + " Mo";
  }

  /** Taille approximative d'une image en dataUrl (base64). */
  function tailleDataUrl(dataUrl) {
    const base64 = String(dataUrl || "").split(",")[1] || "";
    return Math.round(base64.length * 3 / 4);
  }

  /* ---------- Photos ---------- */

  /**
   * Réduit et compresse une photo prise à l'appareil (souvent 3–8 Mo)
   * en JPEG d'environ 100 Ko, stockable et publiable sans alourdir.
   */
  async function compresserImage(fichier, coteMax = 1100, qualite = 0.72) {
    let source;
    try {
      source = await chargerImage(fichier);
    } catch (err) {
      /* HEIC/HEIF : format des iPhone et Android récents, que les
         navigateurs ne décodent pas. L'application Android le convertit
         d'elle-même ; sur le web il faut une photo JPEG ou PNG. */
      const nom = (fichier && fichier.name ? fichier.name : "").toLowerCase();
      const type = (fichier && fichier.type ? fichier.type : "").toLowerCase();
      if (/\.hei[cf]$/.test(nom) || type.includes("heic") || type.includes("heif")) {
        throw new Error("Photo au format HEIC : utilisez l'application Android, " +
          "ou enregistrez-la en JPEG avant de l'ajouter.");
      }
      throw new Error("Photo illisible (format non pris en charge).");
    }
    const l = source.width, h = source.height;
    const ratio = Math.min(1, coteMax / Math.max(l, h));
    const cl = Math.max(1, Math.round(l * ratio));
    const ch = Math.max(1, Math.round(h * ratio));

    const toile = document.createElement("canvas");
    toile.width = cl;
    toile.height = ch;
    const ctx = toile.getContext("2d");
    ctx.imageSmoothingQuality = "high";
    ctx.fillStyle = "#FFFFFF"; // fond blanc pour les PNG transparents
    ctx.fillRect(0, 0, cl, ch);
    ctx.drawImage(source, 0, 0, cl, ch);
    if (source.close) source.close();

    return { dataUrl: toile.toDataURL("image/jpeg", qualite), largeur: cl, hauteur: ch };
  }

  function chargerImage(fichier) {
    // createImageBitmap redresse la photo selon l'orientation EXIF du téléphone.
    if (typeof createImageBitmap === "function") {
      return createImageBitmap(fichier, { imageOrientation: "from-image" }).catch(() => viaBalise(fichier));
    }
    return viaBalise(fichier);
  }

  function viaBalise(fichier) {
    return new Promise((resolve, reject) => {
      const lecteur = new FileReader();
      lecteur.onerror = () => reject(new Error("Lecture de l'image impossible"));
      lecteur.onload = () => {
        const img = new Image();
        img.onload = () => resolve(img);
        img.onerror = () => reject(new Error("Image illisible"));
        img.src = lecteur.result;
      };
      lecteur.readAsDataURL(fichier);
    });
  }

  /** dataUrl -> nouvelle dataUrl réduite (pour les vignettes de listes). */
  async function vignetteDepuisDataUrl(dataUrl, cote = 300) {
    const blob = await (await fetch(dataUrl)).blob();
    const { dataUrl: petite } = await compresserImage(blob, cote, 0.66);
    return petite;
  }

  return {
    pad, uid, echapper,
    fmtNombre, fmtMontant, lireNombre, remisePourcent,
    fmtDateHeure, fmtDate, fmtHeure,
    normaliserTel, lienWhatsApp,
    sansAccent, tempo, telecharger, tailleLisible, tailleDataUrl,
    compresserImage, vignetteDepuisDataUrl,
  };
})();
