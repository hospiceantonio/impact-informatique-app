/* =========================================================
   BIZZOO — le banc du nom des lieux (3.76.0)

   CE QU'ON DÉFEND ICI.
     1. « nommer » un point : déjà connu (à 50 m près) → la source n'est
        pas redemandée ; sinon OpenStreetMap, avec un User-Agent qui nomme
        l'application, puis le nom est noté en base avec la clé de SERVICE.
     2. Le nom se lit du plus précis au plus large : « Sèdomey, Togoudo,
        Godomey » — sans « 12ᵉ Arrondissement », sans doublon.
     3. Hors du Bénin, ou position absurde : refusé, rien n'est demandé.
     4. « chercher » : au Bénin, le Grand Cotonou préféré ; moins de deux
        lettres, rien.
     5. Plafond du jour atteint, source en panne : aucun nom, rien ne bloque.
     6. La clé de service n'apparaît dans aucun journal.

   La source et la base sont des DOUBLURES : aucun appel ne sort.
   Usage :  tools/eprouver-lieu.sh
   ========================================================= */
const dire = console.log.bind(console);
const rouge = (s) => "\x1b[31m" + s + "\x1b[0m";
const vert = (s) => "\x1b[32m" + s + "\x1b[0m";
const gris = (s) => "\x1b[90m" + s + "\x1b[0m";

const SECRETS = { SUPABASE_URL: "https://base.essai", SUPABASE_SERVICE_ROLE_KEY: "cle-de-service-qui-ne-sort-jamais" };
const portes = [];
globalThis.Deno = { env: { get: (n) => SECRETS[n] }, serve: (h) => portes.push(h) };
const journal = [];
for (const voie of ["log", "error", "warn"]) console[voie] = (...a) => journal.push(a.map(String).join(" "));

const monde = {};
const reponse = (corps, statut = 200) => new Response(typeof corps === "string" ? corps : JSON.stringify(corps),
  { status: statut, headers: { "Content-Type": "application/json" } });

globalThis.fetch = async (url, o = {}) => {
  const a = String(url);
  if (a === SECRETS.SUPABASE_URL + "/rest/v1/rpc/lieu_connu") {
    monde.base.push({ fn: "lieu_connu", cle: o.headers.Authorization, corps: JSON.parse(o.body) });
    return monde.connu();
  }
  if (a === SECRETS.SUPABASE_URL + "/rest/v1/rpc/noter_lieu") {
    monde.base.push({ fn: "noter_lieu", cle: o.headers.Authorization, corps: JSON.parse(o.body) });
    return reponse(true);
  }
  if (a === SECRETS.SUPABASE_URL + "/rest/v1/rpc/compter_recherche_lieu") {
    monde.base.push({ fn: "compter_recherche_lieu" });
    return reponse(1);
  }
  /* (3.76.0) OpenStreetMap refuse les fonctions serveur : la question
     passe par la base (pg_net), qui la pose, puis rend la réponse. */
  if (a === SECRETS.SUPABASE_URL + "/rest/v1/rpc/lieu_source_demander") {
    const chemin = JSON.parse(o.body).chemin;
    const url = "https://nominatim.openstreetmap.org" + chemin;
    monde.source.push({ url, cle: o.headers.Authorization });
    const id = ++monde.dernier;
    const rep = await monde.osm(url);
    monde.reponses.set(id, { statut: rep.status, corps: await rep.text(), attente: monde.attente });
    return reponse(id);
  }
  if (a === SECRETS.SUPABASE_URL + "/rest/v1/rpc/lieu_source_reponse") {
    const r = monde.reponses.get(JSON.parse(o.body).demande);
    if (!r || r.attente-- > 0) return reponse("null");      // pas encore là
    return reponse({ statut: r.statut, corps: r.corps, erreur: null });
  }
  throw new Error("adresse inattendue : " + a);
};

const INVERSE = { address: { quarter: "Sèdomey", suburb: "Togoudo", town: "Godomey", county: "Abomey-Calavi",
  country: "Bénin" }, name: "" };
function decor(r = {}) {
  monde.base = []; monde.source = []; monde.reponses = new Map(); monde.dernier = monde.dernier || 0;
  monde.attente = r.attente ?? 1;
  monde.connu = r.connu ?? (() => reponse({ nom: null, plafond_atteint: false }));
  monde.osm = r.osm ?? ((a) => reponse(a.includes("/reverse") ? INVERSE : [
    { lat: "6.3793", lon: "2.4020", name: "Agla", display_name: "Agla, 13ᵉ Arrondissement, Cotonou, Littoral, Bénin",
      address: { suburb: "Agla", city_district: "13ᵉ Arrondissement", city: "Cotonou" } },
    { lat: "48.85", lon: "2.35", name: "Agla", display_name: "Ailleurs, France", address: { city: "Paris" } },
  ]));
  journal.length = 0;
}

let echecs = 0;
const verifie = (v, q) => { if (v) dire("  " + gris("ok") + "    " + q); else { echecs++; dire("  " + rouge("ÉCHEC") + " " + q); } };
const titre = (q) => { dire(""); dire("== " + q); };

const module = await import("../lieu/index.ts");
const porte = portes.pop();
async function appeler(corps) {
  const r = await porte(new Request("https://fonction.essai/lieu", { method: "POST", body: JSON.stringify(corps) }));
  return { statut: r.status, d: await r.json().catch(() => null), cors: r.headers.get("Access-Control-Allow-Origin") };
}
const ICI = { latitude: 6.4012, longitude: 2.3401 };
let r;

titre("1. Nommer un point");
decor({ connu: () => reponse({ nom: "Sèdomey, Togoudo, Godomey", plafond_atteint: false }) });
r = await appeler({ action: "nommer", ...ICI });
verifie(r.d.nom === "Sèdomey, Togoudo, Godomey" && r.d.cache === true && !monde.source.length,
  "déjà connu : rendu tel quel, la source n'est pas redemandée");
verifie(r.cors === "*", "le navigateur peut l'appeler (CORS)");
decor();
r = await appeler({ action: "nommer", ...ICI });
verifie(monde.source.length === 1 && /\/reverse\?/.test(monde.source[0].url) &&
  monde.source[0].cle === "Bearer " + SECRETS.SUPABASE_SERVICE_ROLE_KEY,
  "inconnu : la question à OpenStreetMap passe par la base, avec la clé de service");
verifie(r.d.nom === "Sèdomey, Togoudo, Godomey", "« Sèdomey, Togoudo, Godomey » (" + r.d.nom + ")");
const note = monde.base.find((b) => b.fn === "noter_lieu");
verifie(note && note.corps.nom === "Sèdomey, Togoudo, Godomey" && note.cle === "Bearer " + SECRETS.SUPABASE_SERVICE_ROLE_KEY,
  "et noté en base, avec la clé de service");

titre("2. Le nom, du plus précis au plus large");
verifie(module.nomDuLieu({ suburb: "Agla", city_district: "13ᵉ Arrondissement", city: "Cotonou" }) === "Agla, Cotonou",
  "sans l'arrondissement : « Agla, Cotonou »");
verifie(module.nomDuLieu({ quarter: "Womey", suburb: "Womey", town: "Abomey-Calavi" }) === "Womey, Abomey-Calavi",
  "sans doublon : « Womey, Abomey-Calavi »");
verifie(module.nomDuLieu({ quarter: "A", suburb: "B", town: "C", city: "D" }, "Marché") === "Marché, A, B",
  "trois au plus, le nom du lieu d'abord");

titre("3. Hors du Bénin : refusé, rien n'est demandé");
for (const p of [{ latitude: 48.85, longitude: 2.35 }, { latitude: 0, longitude: 0 }, { latitude: "x", longitude: 2 }]) {
  decor();
  r = await appeler({ action: "nommer", ...p });
  verifie(r.statut === 400 && !monde.source.length && !monde.base.length, "refusé : " + JSON.stringify(p));
}

titre("4. Chercher un lieu par son nom");
decor();
r = await appeler({ action: "chercher", q: "Agla" });
verifie(monde.source.length === 1 && /countrycodes=bj/.test(monde.source[0].url) && /viewbox=/.test(monde.source[0].url),
  "au Bénin, le Grand Cotonou préféré");
verifie(r.d.resultats.length === 1 && r.d.resultats[0].nom === "Agla, Cotonou" && r.d.resultats[0].latitude === 6.3793,
  "un résultat hors du Bénin est écarté ; « Agla, Cotonou » (" + JSON.stringify(r.d.resultats) + ")");
verifie(monde.base.some((b) => b.fn === "compter_recherche_lieu"), "la recherche compte dans le plafond du jour");
decor();
r = await appeler({ action: "chercher", q: " a " });
verifie(r.d.resultats.length === 0 && !monde.source.length, "moins de deux lettres : rien, et rien n'est demandé");

titre("5. Plafond, panne : aucun nom, rien ne bloque");
decor({ connu: () => reponse({ nom: null, plafond_atteint: true }) });
r = await appeler({ action: "nommer", ...ICI });
verifie(r.statut === 200 && r.d.nom === null && !monde.source.length, "plafond du jour atteint : la source n'est pas appelée");
decor({ osm: () => reponse("panne", 503) });
r = await appeler({ action: "nommer", ...ICI });
verifie(r.statut === 200 && r.d.nom === null && !monde.base.some((b) => b.fn === "noter_lieu"), "source en panne : pas de nom, rien d'écrit");
decor({ connu: () => reponse("", 500) });
r = await appeler({ action: "chercher", q: "Agla" });
verifie(r.statut === 200 && Array.isArray(r.d.resultats) && !r.d.resultats.length, "base en panne : une liste vide, sans erreur 500");

titre("5 bis. La réponse qui ne vient pas ; un nom tapé avec des parenthèses");
decor({ attente: 1e9 });
const debut = Date.now();
let refus = null;
try { await module.source("/reverse?format=jsonv2&lat=6.4&lon=2.3", undefined, 600, 50); } catch (e) { refus = e; }
verifie(refus && /pas de réponse/.test(refus.message) && Date.now() - debut < 2000,
  "pas de réponse dans le délai : abandon, sans attendre indéfiniment");
verifie(module.coder("Akpakpa (Dodomè)!") === "Akpakpa%20%28Dodom%C3%A8%29%21",
  "les parenthèses et « ! » sont codées : la base ne refuse pas la question");
decor();
r = await appeler({ action: "chercher", q: "Agla (Cotonou)" });
verifie(/q=Agla%20%28Cotonou%29$/.test(monde.source[0].url), "la recherche part codée (" + monde.source[0].url.slice(-24) + ")");

titre("6. Les clés ne fuient pas");
verifie(!journal.some((l) => l.includes(SECRETS.SUPABASE_SERVICE_ROLE_KEY)), "la clé de service n'est dans aucun journal");

dire("");
if (echecs) { dire(rouge(echecs + " constat(s) en échec ✘")); process.exit(1); }
dire(vert("Le nom des lieux : demandé une fois, noté pour tous, jamais bloquant ✔"));
