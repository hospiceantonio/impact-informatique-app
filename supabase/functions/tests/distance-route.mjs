/* =========================================================
   BIZZOO — le banc de la distance par la route (3.70.0)

   CE QU'ON DÉFEND ICI.
     1. SANS CLÉ GOOGLE, RIEN : { actif: false }, et ni la base ni Google
        ne sont appelés — tout continue à vol d'oiseau.
     2. Une position invalide ne coûte rien (ni base, ni Google).
     3. Une distance déjà connue (à 50 m près) ne rappelle pas Google.
     4. Sinon, Google est appelé avec la clé, le champ « distance » seul
        (le tarif le moins cher), et la distance est écrite dans la base
        avec la clé de SERVICE.
     5. Trop loin, plafond du jour atteint, Google en panne ou muet :
        aucune distance, aucune écriture — la commande ne bloque pas.
     6. Les clés n'apparaissent dans aucun journal.

   Google et la base sont des DOUBLURES : aucun appel ne sort.
   Usage :  tools/eprouver-distance-route.sh
   ========================================================= */
const dire = console.log.bind(console);
const rouge = (s) => "\x1b[31m" + s + "\x1b[0m";
const vert = (s) => "\x1b[32m" + s + "\x1b[0m";
const gris = (s) => "\x1b[90m" + s + "\x1b[0m";

const SECRETS = {
  SUPABASE_URL: "https://base.essai",
  SUPABASE_SERVICE_ROLE_KEY: "cle-de-service-qui-ne-sort-jamais",
  GOOGLE_MAPS_KEY: "cle-google-qui-ne-sort-jamais",
};
const portes = [];
globalThis.Deno = { env: { get: (n) => SECRETS[n] }, serve: (h) => portes.push(h) };
const journal = [];
for (const voie of ["log", "error", "warn"]) console[voie] = (...a) => journal.push(a.map(String).join(" "));

const monde = {};
const reponse = (corps, statut = 200) => new Response(
  typeof corps === "string" ? corps : JSON.stringify(corps),
  { status: statut, headers: { "Content-Type": "application/json" } });
const POINT = { latitude: 6.4105, longitude: 2.3402 };

globalThis.fetch = async (url, o = {}) => {
  const a = String(url);
  if (a === SECRETS.SUPABASE_URL + "/rest/v1/rpc/route_connue") {
    monde.connue.push({ cle: o.headers.Authorization, corps: JSON.parse(o.body) });
    return monde.base_connue();
  }
  if (a === SECRETS.SUPABASE_URL + "/rest/v1/rpc/enregistrer_route") {
    monde.ecrites.push({ cle: o.headers.Authorization, corps: JSON.parse(o.body) });
    return reponse({ ok: true });
  }
  if (a === "https://routes.googleapis.com/directions/v2:computeRoutes") {
    monde.google.push({ cle: o.headers["X-Goog-Api-Key"], champs: o.headers["X-Goog-FieldMask"],
      corps: JSON.parse(o.body) });
    return monde.google_reponse();
  }
  throw new Error("adresse inattendue : " + a);
};

function decor(r = {}) {
  monde.connue = []; monde.ecrites = []; monde.google = [];
  monde.base_connue = r.connue ?? (() => reponse({ point: true, origine: POINT, distance_m: null,
    vol_oiseau_km: 4.2, plafond_atteint: false }));
  monde.google_reponse = r.google ?? (() => reponse({ routes: [{ distanceMeters: 7340 }] }));
  journal.length = 0;
}

let echecs = 0;
const verifie = (v, q) => { if (v) dire("  " + gris("ok") + "    " + q); else { echecs++; dire("  " + rouge("ÉCHEC") + " " + q); } };
const titre = (q) => { dire(""); dire("== " + q); };

await import("../distance-route/index.ts");
const porte = portes.pop();
async function appeler(corps, methode = "POST") {
  const r = await porte(new Request("https://fonction.essai/distance-route", {
    method: methode, body: methode === "POST" ? JSON.stringify(corps) : undefined }));
  return { statut: r.status, d: await r.json().catch(() => null), cors: r.headers.get("Access-Control-Allow-Origin") };
}
const CLIENT = { latitude: 6.3700, longitude: 2.3900 };

titre("1. Sans clé Google, rien ne se passe");
const cle = SECRETS.GOOGLE_MAPS_KEY;
SECRETS.GOOGLE_MAPS_KEY = "";
decor();
let r = await appeler(CLIENT);
verifie(r.statut === 200 && r.d.actif === false && !monde.connue.length && !monde.google.length,
  "{ actif: false }, sans appeler ni la base ni Google");
SECRETS.GOOGLE_MAPS_KEY = cle;
r = await appeler(null, "OPTIONS");
verifie(r.statut === 200 && r.cors === "*", "le navigateur peut l'appeler (CORS)");
r = await appeler(null, "GET");
verifie(r.statut === 405, "autre chose que POST : 405");

titre("2. Une position invalide ne coûte rien");
decor();
for (const faux of [{}, { latitude: "abc", longitude: 2 }, { latitude: 95, longitude: 2 }, { latitude: 0, longitude: 0 }]) {
  r = await appeler(faux);
  verifie(r.statut === 400 && !monde.connue.length && !monde.google.length, "refusée : " + JSON.stringify(faux));
}

titre("3. Déjà connue : Google n'est pas rappelé");
decor({ connue: () => reponse({ point: true, origine: POINT, distance_m: 6120, vol_oiseau_km: 4.2 }) });
r = await appeler(CLIENT);
verifie(monde.connue[0] && monde.connue[0].cle === "Bearer " + SECRETS.SUPABASE_SERVICE_ROLE_KEY &&
  monde.connue[0].corps.latitude === CLIENT.latitude, "route_connue(position), avec la clé de service");
verifie(r.d.actif === true && r.d.distance_km === 6.12 && r.d.cache === true && !monde.google.length && !monde.ecrites.length,
  "6,12 km rendus depuis la base, sans appel à Google ni écriture");

titre("4. Nouvelle : Google, puis la base");
decor();
r = await appeler(CLIENT);
const g = monde.google[0] || {};
verifie(g.cle === SECRETS.GOOGLE_MAPS_KEY && g.champs === "routes.distanceMeters",
  "Google appelé avec la clé, pour la distance seule (tarif « Essentials »)");
verifie(g.corps && g.corps.origin.location.latLng.latitude === POINT.latitude &&
  g.corps.destination.location.latLng.longitude === CLIENT.longitude && g.corps.travelMode === "DRIVE" &&
  g.corps.routingPreference === "TRAFFIC_UNAWARE", "du point BIZZOO au client, par la route, sans trafic");
verifie(monde.ecrites.length === 1 && monde.ecrites[0].corps.distance_m === 7340 &&
  monde.ecrites[0].cle === "Bearer " + SECRETS.SUPABASE_SERVICE_ROLE_KEY,
  "enregistrer_route(…, 7340 m), avec la clé de service");
verifie(r.d.actif === true && r.d.distance_km === 7.34 && r.d.cache === false, "7,34 km rendus à l'écran");

titre("5. Ce qui ne donne pas de distance ne bloque rien");
decor({ connue: () => reponse({ point: false }) });
r = await appeler(CLIENT);
verifie(r.d.actif === false && !monde.google.length, "point BIZZOO pas réglé : inactif, Google pas appelé");
decor({ connue: () => reponse({ point: true, origine: POINT, distance_m: null, vol_oiseau_km: 480 }) });
r = await appeler(CLIENT);
verifie(r.d.distance_km === null && !monde.google.length, "à 480 km : trop loin, Google pas appelé");
decor({ connue: () => reponse({ point: true, origine: POINT, distance_m: null, vol_oiseau_km: 4, plafond_atteint: true }) });
r = await appeler(CLIENT);
verifie(r.d.distance_km === null && !monde.google.length, "plafond du jour atteint : Google pas appelé");
decor({ google: () => reponse({ error: { code: 403, message: "API key not valid" } }, 403) });
r = await appeler(CLIENT);
verifie(r.statut === 200 && r.d.distance_km === null && !monde.ecrites.length, "Google refuse : pas de distance, rien d'écrit");
decor({ google: () => reponse({}) });
r = await appeler(CLIENT);
verifie(r.d.distance_km === null && !monde.ecrites.length, "Google ne rend aucun trajet : idem");
decor({ google: () => { throw new Error("réseau coupé"); } });
r = await appeler(CLIENT);
verifie(r.statut === 200 && r.d.distance_km === null && !monde.ecrites.length, "Google injoignable : idem, sans erreur 500");
decor({ connue: () => reponse("", 500) });
r = await appeler(CLIENT);
verifie(r.statut === 200 && r.d.distance_km === null && !monde.google.length, "la base en panne : idem");

titre("6. Les clés ne fuient pas");
verifie(!journal.some((l) => l.includes(SECRETS.SUPABASE_SERVICE_ROLE_KEY) || l.includes(SECRETS.GOOGLE_MAPS_KEY)),
  "ni la clé de service ni la clé Google dans un journal");

dire("");
if (echecs) { dire(rouge(echecs + " constat(s) en échec ✘")); process.exit(1); }
dire(vert("La distance par la route : Google seulement quand il le faut, la base seule juge ✔"));
