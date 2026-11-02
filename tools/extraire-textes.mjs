/* =========================================================
   Relever les textes français d'une application (3.73.0)

   Usage :
     ACORN=<chemin>/acorn/dist/acorn.mjs node tools/extraire-textes.mjs client
     node tools/extraire-textes.mjs client --construire

   1. Sans option : lit les fichiers js/ et index.html de l'application,
      relève chaque texte que l'écran peut afficher (chaînes, morceaux de
      HTML, attributs placeholder / title / aria-label / alt), et écrit
      i18n/<app>.textes.json — la liste, triée, sans doublon. Les textes
      déjà traduits dans i18n/<app>.en.json y sont marqués ; ceux qui
      manquent sont listés dans i18n/<app>.a-traduire.json.
   2. --construire : assemble le dictionnaire que lit js/langue.js —
      <app>/js/traductions-en.js — à partir de i18n/en.json (toutes les
      traductions ; l'application n'emporte que ses textes), de
      i18n/commun.en.json (textes partagés : notifications de la base…),
      de i18n/<app>.en.json (ses corrections) et des motifs
      i18n/<app>.motifs.json + i18n/commun.motifs.json.

   Le dictionnaire reste du texte : une ligne « français » → « anglais ».
   Corriger une traduction, c'est corriger i18n/en.json (ou, pour une
   seule application, i18n/<app>.en.json) puis relancer --construire.
   ========================================================= */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const RACINE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const app = process.argv[2];
const construire = process.argv.includes("--construire");
if (!["client", "admin", "personnel", "vitrine", "serveur"].includes(app)) {
  console.error("Usage : node tools/extraire-textes.mjs client|admin|personnel|vitrine|serveur [--construire]");
  process.exit(2);
}
const I18N = path.join(RACINE, "i18n");
fs.mkdirSync(I18N, { recursive: true });
const lireJson = (f, defaut) => {
  try { return JSON.parse(fs.readFileSync(path.join(I18N, f), "utf8")); } catch (_) { return defaut; }
};

/* ---------- Le dictionnaire des fonctions Edge ----------
   Les notifications et les alertes que la base envoie sur les téléphones
   (envoyer-push, rh-push) : textes communs et motifs, rien d'autre. */
if (app === "serveur") {
  const exact = lireJson("commun.en.json", {});
  const motifs = lireJson("commun.motifs.json", []);
  for (const [m] of motifs) new RegExp(m, "u");
  const sortie = path.join(RACINE, "supabase", "functions", "_partage", "traductions-en.ts");
  fs.writeFileSync(sortie,
    "/* Fabriqué par tools/extraire-textes.mjs serveur, à partir de i18n/commun.*. Ne pas modifier à la main. */\n" +
    "export const EXACT: Record<string, string> = " + JSON.stringify(exact) + ";\n" +
    "export const MOTIFS: [string, string][] = " + JSON.stringify(motifs) + ";\n");
  console.log(path.relative(RACINE, sortie) + " : " + Object.keys(exact).length + " textes, " + motifs.length + " motifs.");
  process.exit(0);
}

/* ---------- Construire le dictionnaire ---------- */
if (construire) {
  /* i18n/en.json : TOUTES les traductions, des trois applications et de la
     vitrine. Chaque application n'en emporte que ses propres textes
     (i18n/<app>.textes.json), plus les textes communs (i18n/commun.en.json :
     les notifications de la base…) et ses corrections (i18n/<app>.en.json). */
  const tout = lireJson("en.json", {});
  const siens = Object.keys(lireJson(app + ".textes.json", {}));
  const exact = { ...Object.fromEntries(siens.filter((k) => tout[k]).map((k) => [k, tout[k]])),
    ...(app === "vitrine" ? {} : lireJson("commun.en.json", {})), ...lireJson(app + ".en.json", {}) };
  for (const [k, v] of Object.entries(exact)) if (!v || typeof v !== "string" || v === k) delete exact[k];
  /* La vitrine n'affiche aucune notification : pas de textes communs. */
  const motifs = [...lireJson(app + ".motifs.json", []), ...(app === "vitrine" ? [] : lireJson("commun.motifs.json", []))];
  for (const [m] of motifs) new RegExp(m, "u");          // un motif cassé arrête tout, ici
  const sortie = app === "vitrine" ? path.join(RACINE, "vitrine", "traductions-en.js")
    : path.join(RACINE, app, "js", "traductions-en.js");
  fs.writeFileSync(sortie,
    "/* Fabriqué par tools/extraire-textes.mjs " + app + " --construire, à partir de i18n/. Ne pas modifier à la main. */\n" +
    "window.BIZZOO_EN = " + JSON.stringify({ exact, motifs }) + ";\n");
  console.log(path.relative(RACINE, sortie) + " : " + Object.keys(exact).length + " textes, " + motifs.length + " motifs.");
  process.exit(0);
}

/* ---------- Relever les textes ---------- */
const acornChemin = process.env.ACORN || "acorn";
const acorn = await import(acornChemin.startsWith("/") ? pathToFileURL(acornChemin).href : acornChemin);

const ENTITES = { nbsp: " ", amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", laquo: "«", raquo: "»",
  hellip: "…", rsquo: "’", lsquo: "‘", ndash: "–", mdash: "—", middot: "·", euro: "€", deg: "°", times: "×" };
const decoder = (t) => t.replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, (m, c) => {
  if (c[0] === "#") return String.fromCodePoint(c[1] === "x" || c[1] === "X" ? parseInt(c.slice(2), 16) : parseInt(c.slice(1), 10));
  return ENTITES[c.toLowerCase()] ?? m;
});

/** Un texte qu'un humain lit, pas du code. */
function naturel(brut) {
  const s = brut.trim();
  if (s.length < 2 || !/[A-Za-zÀ-ÿ]{2}/.test(s)) return false;
  if (/^(https?:|mailto:|tel:|data:|#\/|\.\/|\/)/.test(s)) return false;
  /* Du code — mais pas le « ; » d'une phrase française, entouré d'espaces. */
  if (/=>|[{}]|;(?=\S)|;$|\$\{|\\n|\bfunction\b|\breturn\b/.test(s)) return false;
  if (/^[a-z]+(_[a-z0-9]+)+$/.test(s)) return false;                 // snake_case
  if (/^[a-z]+[A-Z][A-Za-z0-9]*$/.test(s)) return false;             // camelCase
  if (/^[A-Z0-9_ -]{1,6}$/.test(s)) return false;                     // MTN, FCFA, BZ-…
  if (/^[#.\[]|^\w+\[|\]$/.test(s) && !/\s[a-zà-ÿ]{3,}\s/.test(s)) return false; // sélecteurs
  if (/^[a-z-]+\s*:\s*[^ ]+$/.test(s)) return false;                 // display:flex
  if (/^(select|order|limit|eq|in|is|not)[=.(]/.test(s) || /[?&](select|order)=/.test(s)) return false;
  if (/^[\w.-]+\.(js|css|png|jpg|jpeg|svg|webp|json|html|apk|mp3|wav)$/i.test(s)) return false;
  if (/^[\w.-]+\/[\w./?=&-]*$/.test(s)) return false;                // rpc/…, chemins
  if (/^[\w-]+(\.[\w-]+)+$/.test(s)) return false;                  // www.bizzoomarket.com
  if (/^[A-Z][a-z]+[A-Z]\w*$/.test(s)) return false;                 // ViewContent
  if (/[<>"=]/.test(s.replace(/«|»/g, "")) && !/\s[a-zà-ÿ]{3,}/i.test(s.replace(/[\w-]+=("[^"]*"?|'[^']*'?)/g, ""))) return false;
  if (/^[a-z0-9-]+$/.test(s)) {
    /* Un mot seul en minuscules : un texte s'il porte un accent, ou s'il
       était entouré d'espaces (« 5 » + " commandes "). */
    return /[à-ÿ]/.test(s) || brut !== s;
  }
  return true;
}

const textes = new Map();      // texte → première source
function noter(t, source) {
  const brut = decoder(t);
  if (!naturel(brut)) return;
  const s = brut.trim().replace(/\s+/g, " ");
  if (!textes.has(s)) textes.set(s, source);
}

/** Un morceau de HTML : les textes entre balises, et les attributs lus. */
function depuisHtml(v, source) {
  for (const m of v.matchAll(/\b(placeholder|title|aria-label|alt|data-titre)\s*=\s*"([^"]*)"/g)) noter(m[2], source);
  for (const m of v.matchAll(/\b(placeholder|title|aria-label|alt|data-titre)\s*=\s*'([^']*)'/g)) noter(m[2], source);
  const sansBalises = v.replace(/<(script|style)[\s\S]*?<\/\1>/gi, " ").split(/<[^>]*>/);
  for (const morceau of sansBalises) noter(morceau, source);
}

function depuisChaine(v, source) {
  /* Les morceaux de HTML coupés par une concaténation : « '" data-x="' »,
     « '<a class="puce' », « '">' + nom ». On garde les attributs lus, puis
     on retire balises et bouts d'attributs avant de chercher le texte. */
  if (/[<>]|[\w-]+="/.test(v)) {
    for (const m of v.matchAll(/\b(placeholder|title|aria-label|alt|data-titre)\s*=\s*"([^"]*)"/g)) noter(m[2], source);
    const nettoye = v.replace(/<(script|style)[\s\S]*?<\/\1>/gi, " ")
      .replace(/<\/?[a-z][^>]*>?/gi, "\u0000")                 // balises, même ouvertes
      .replace(/(^|\s)[\w:-]+\s*=\s*("[^"]*"?|'[^']*'?)/g, "\u0000")   // attributs, même coupés
      .replace(/^[^<>\u0000]*?"\s*>/, "\u0000")                // « …">» en tête
      .replace(/^\s*"|"\s*$/g, "\u0000");
    for (const morceau of nettoye.split(/[\u0000<>]/)) noter(morceau, source);
  } else {
    noter(v, source);
  }
}

const dossier = app === "vitrine" ? RACINE : path.join(RACINE, app);
const fichiersJs = app === "vitrine" ? [] : [
  ...fs.readdirSync(path.join(dossier, "js")).filter((f) => f.endsWith(".js")).map((f) => path.join(dossier, "js", f)),
  ...(fs.existsSync(path.join(dossier, "js", "vues")) ? fs.readdirSync(path.join(dossier, "js", "vues"))
    .filter((f) => f.endsWith(".js")).map((f) => path.join(dossier, "js", "vues", f)) : []),
].filter((f) => !/(traductions-en|langue)\.js$/.test(f));

for (const f of fichiersJs) {
  const code = fs.readFileSync(f, "utf8");
  const rel = path.relative(RACINE, f);
  let arbre;
  try { arbre = acorn.parse(code, { ecmaVersion: "latest", sourceType: "script", locations: true, allowHashBang: true }); }
  catch (e) { console.error("Illisible : " + rel + " — " + e.message); process.exit(1); }
  /* « 'Une phrase écrite ' + 'sur deux lignes' » : à l'écran, c'est UN texte.
     On recolle les chaînes voisines d'une addition (et les gabarits sans
     ${…}) avant de relever ; les valeurs calculées coupent le texte. */
  const constante = (x) => (x.type === "Literal" && typeof x.value === "string") ? x.value
    : (x.type === "TemplateLiteral" && x.expressions.length === 0) ? (x.quasis[0].value.cooked || "") : null;
  function aplatir(x, sortie) {
    if (x.type === "BinaryExpression" && x.operator === "+") { aplatir(x.left, sortie); aplatir(x.right, sortie); }
    else sortie.push(x);
    return sortie;
  }
  (function marcher(n, parent) {
    if (!n || typeof n.type !== "string") return;
    if (n.type === "BinaryExpression" && n.operator === "+" && !(parent && parent.type === "BinaryExpression" && parent.operator === "+")) {
      const morceaux = aplatir(n, []);
      if (morceaux.some((x) => constante(x) !== null)) {
        let courant = null;
        const autres = [];
        for (const x of morceaux) {
          const c = constante(x);
          if (c !== null) courant = (courant ?? "") + c;
          else { if (courant !== null) depuisChaine(courant, rel + ":" + n.loc.start.line); courant = null; autres.push(x); }
        }
        if (courant !== null) depuisChaine(courant, rel + ":" + n.loc.start.line);
        for (const x of autres) marcher(x, n);
        return;
      }
    }
    if (n.type === "Literal" && typeof n.value === "string") {
      /* Les clés d'objet et les noms de propriété ne s'affichent pas. */
      const cle = parent && ((parent.type === "Property" && parent.key === n) || (parent.type === "MemberExpression" && parent.property === n));
      if (!cle && !(parent && parent.type === "ImportDeclaration")) depuisChaine(n.value, rel + ":" + n.loc.start.line);
    } else if (n.type === "TemplateLiteral") {
      for (const q of n.quasis) depuisChaine(q.value.cooked || "", rel + ":" + q.loc.start.line);
    }
    for (const k of Object.keys(n)) {
      if (k === "loc" || k === "start" || k === "end") continue;
      const v = n[k];
      if (Array.isArray(v)) v.forEach((x) => marcher(x, n));
      else if (v && typeof v.type === "string") marcher(v, n);
    }
  })(arbre, null);
}

const pages = app === "vitrine"
  ? ["index.html", "404.html", ...fs.readdirSync(path.join(RACINE, "legal")).map((f) => path.join("legal", f))].map((f) => path.join(RACINE, f))
  : [path.join(dossier, "index.html")];
for (const p of pages) {
  const html = fs.readFileSync(p, "utf8").replace(/<script[\s\S]*?<\/script>/gi, " ").replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, " ");
  const titre = html.match(/<title>([\s\S]*?)<\/title>/i);
  if (titre) noter(titre[1], path.relative(RACINE, p));
  for (const m of html.matchAll(/<meta[^>]+(name|property)="(description|og:title|og:description)"[^>]*content="([^"]*)"/gi)) noter(m[3], path.relative(RACINE, p));
  depuisHtml(html.replace(/[\s\S]*<body[^>]*>/i, ""), path.relative(RACINE, p));
}

const traduits = { ...lireJson("en.json", {}), ...lireJson("commun.en.json", {}), ...lireJson(app + ".en.json", {}) };
const liste = [...textes.keys()].sort((a, b) => a.localeCompare(b, "fr"));
const manque = liste.filter((t) => !traduits[t]);
fs.writeFileSync(path.join(I18N, app + ".textes.json"), JSON.stringify(Object.fromEntries(liste.map((t) => [t, textes.get(t)])), null, 1) + "\n");
fs.writeFileSync(path.join(I18N, app + ".a-traduire.json"), JSON.stringify(manque, null, 1) + "\n");
console.log(app + " : " + liste.length + " textes relevés, " + (liste.length - manque.length) + " traduits, " + manque.length + " à traduire.");
