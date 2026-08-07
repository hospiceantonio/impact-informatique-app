/* =========================================================
   Utilitaires : textes, montants, téléphone, WhatsApp.
   ========================================================= */
const Utils = (() => {

  const MOIS = ["janvier","février","mars","avril","mai","juin","juillet","août","septembre","octobre","novembre","décembre"];

  const pad = (n, len = 2) => String(n).padStart(len, "0");

  function echapper(valeur) {
    return String(valeur === null || valeur === undefined ? "" : valeur)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  /* ---------- Montants ---------- */

  /** "385 000" — lisible sur petit écran. */
  function fmtNombre(n) {
    const v = Math.round(Number(n) || 0);
    return String(Math.abs(v)).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  }

  function fmtMontant(n, devise) {
    const v = Math.round(Number(n) || 0);
    const signe = v < 0 ? "-" : "";
    return signe + fmtNombre(v) + (devise ? " " + devise : "");
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

  function lienTel(tel, indicatif) {
    const num = normaliserTel(tel, indicatif);
    return num ? "tel:+" + num : "";
  }

  /* ---------- Divers ---------- */

  /** Comparaison insensible aux accents et à la casse, pour la recherche. */
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

  /** Texte multi-lignes -> paragraphes HTML sûrs. */
  function paragraphes(texte) {
    const morceaux = String(texte || "").split(/\n+/).map((l) => l.trim()).filter(Boolean);
    if (!morceaux.length) return "";
    return morceaux.map((l) => "<p>" + echapper(l) + "</p>").join("");
  }

  return {
    pad, echapper,
    fmtNombre, fmtMontant, remisePourcent,
    fmtDateHeure,
    normaliserTel, lienWhatsApp, lienTel,
    sansAccent, tempo, paragraphes,
  };
})();
