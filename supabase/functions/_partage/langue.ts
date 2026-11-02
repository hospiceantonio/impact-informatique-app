/* =========================================================
   BIZZOO — traduire une notification avant de l'envoyer (3.73.0)

   La base écrit ses notifications en français. Un compte qui a choisi
   l'anglais (table langues_comptes, rendue par push_a_envoyer et
   rh_push_a_envoyer) les reçoit traduites sur son téléphone :
     1. ligne par ligne ;
     2. le texte entier s'il est au dictionnaire, sinon le premier motif
        (phrase à trous) qui s'applique ;
     3. sinon les morceaux connus, seulement si le texte en est presque
        entièrement fait — jamais une phrase à moitié traduite.
   Le dictionnaire : traductions-en.ts, fabriqué par
   tools/extraire-textes.mjs serveur à partir de i18n/commun.*. Les mêmes
   règles traduisent ces textes dans les applications (js/langue.js).
   ========================================================= */
import { EXACT, MOTIFS } from "./traductions-en.ts";

const LETTRE = "A-Za-zÀ-ÖØ-öø-ÿŒœ";
const motifs: [RegExp, string][] = MOTIFS.map(([m, r]) => [new RegExp(m, "u"), r]);
const echapper = (t: string) => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const lettre = new RegExp("[" + LETTRE + "]", "u");
const cles = Object.keys(EXACT).filter((k) => k.length >= 4).sort((a, b) => b.length - a.length);
const morceaux = cles.length ? new RegExp(cles.map((k) => (lettre.test(k[0]) ? "(?<![" + LETTRE + "])" : "") + echapper(k) +
  (lettre.test(k[k.length - 1]) ? "(?![" + LETTRE + "])" : "")).join("|"), "gu") : null;

function ligne(texte: string): string {
  const debut = texte.match(/^\s*/)![0];
  const fin = texte.match(/\s*$/)![0];
  const s = texte.slice(debut.length, texte.length - fin.length);
  if (!s) return texte;
  let r: string | undefined = EXACT[s];
  if (r === undefined) {
    for (const [m, remplacement] of motifs) {
      if (m.test(s)) { r = s.replace(m, remplacement); break; }
    }
  }
  /* Ce qu'un motif a laissé de français (un libellé d'alerte) passe par
     les morceaux connus. */
  const base = r ?? s;
  if (morceaux) {
    let trouves = 0;
    const essai = base.replace(morceaux, (t) => (EXACT[t] ? (trouves++, "\u0001" + EXACT[t] + "\u0002") : t));
    if (trouves) {
      const reste = essai.replace(/\u0001[^\u0002]*\u0002/g, " ").replace(/\S+@\S+|https?:\/\/\S+/g, " ");
      const inconnus = (reste.match(new RegExp("(?<![" + LETTRE + "])[a-zà-ÿœ][a-zà-ÿœ'’-]{2,}", "gu")) || []).length;
      if (r !== undefined || (inconnus <= Math.max(1, trouves - 1) && inconnus < 3)) r = essai.replace(/[\u0001\u0002]/g, "");
    }
  }
  return debut + (r ?? s) + fin;
}

/** Le texte dans la langue du destinataire : tel quel en français. */
export function traduire(texte: string, langue: string | null | undefined): string {
  if (langue !== "en" || !texte) return texte;
  return texte.split("\n").map(ligne).join("\n");
}
