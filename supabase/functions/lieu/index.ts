/* =========================================================
   BIZZOO — le nom d'un lieu, et un lieu par son nom (3.76.0)

   Deux questions, posées par les applications :

     « nommer »   un point de la carte → « Sèdomey, Togoudo, Godomey » :
                  le quartier que le livreur lit sur son bon, et que
                  l'adresse de livraison porte désormais ;
     « chercher » « Agla » → les lieux de ce nom au Bénin, pour poser
                  l'épingle sans la promener sur la carte.

   La source : OpenStreetMap (Nominatim), libre et sans clé — interrogée
   PAR LA BASE (pg_net) : il refuse les adresses des fonctions serveur.
   Ses règles :
   une application qui se nomme (User-Agent), pas plus d'une question par
   seconde, et rien de ce qu'il a déjà dit redemandé — d'où LE CACHE EN
   BASE (« lieux_noms », à 50 m près) : un quartier nommé une fois l'est
   pour tout le monde, et le bon du livreur ne coûte plus rien.

   (4.8.0) GOOGLE D'ABORD, quand sa clé est là (le secret GOOGLE_MAPS_KEY,
   le même que « distance-route ») : Geocoding pour nommer un point,
   Places (Text Search) pour chercher — plus précis au Bénin. Il faut que
   « Geocoding API » et « Places API (New) » soient activées et permises à
   la clé. Google ne répond pas (refus, panne, rien trouvé) : on revient à
   OpenStreetMap, comme avant — jamais bloquant. Un nom venu de Google se
   note avec sa source : la base ne le garde que 30 jours.

   Ouverte sans compte (les clients commandent sans), comme
   « distance-route » : rien de ce qu'elle reçoit n'est cru hormis une
   position, bornée au Bénin, ou quelques mots ; un plafond par jour
   protège la source.

     supabase functions deploy lieu --no-verify-jwt
   ========================================================= */

const cleGoogle = () => (Deno.env.get("GOOGLE_MAPS_KEY") ?? "").trim();
const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/* Le Bénin, large : au-delà, ce n'est pas une livraison BIZZOO. */
const BENIN = { latMin: 6.0, latMax: 12.6, lngMin: 0.6, lngMax: 4.0 };
/* Le Grand Cotonou, préféré dans les recherches (« Akpakpa » existe aussi
   dans la Donga) : gauche, haut, droite, bas. */
const PREFERE = "1.85,6.75,2.75,6.25";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (corps: unknown, statut = 200) =>
  new Response(JSON.stringify(corps), { status: statut, headers: { ...CORS, "Content-Type": "application/json" } });

async function base(fonction: string, corps: unknown): Promise<unknown> {
  const r = await fetch(BASE + "/rest/v1/rpc/" + fonction, {
    method: "POST",
    headers: { "apikey": SERVICE, "Authorization": "Bearer " + SERVICE, "Content-Type": "application/json" },
    body: JSON.stringify(corps),
    signal: AbortSignal.timeout(8000),
  });
  if (!r.ok) throw new Error(fonction + " : HTTP " + r.status);
  return await r.json().catch(() => null);
}

type Adresse = Record<string, string | undefined>;

/** « Sèdomey, Togoudo, Godomey » : du plus précis au plus large, trois au plus. */
export function nomDuLieu(a: Adresse | undefined, nom?: string): string {
  if (!a) return String(nom || "").trim();
  const parties = [
    nom && !/^\d/.test(nom) ? nom : "",
    a.quarter || a.neighbourhood || a.hamlet || a.residential || "",
    a.suburb || "",
    a.city_district && !/Arrondissement/i.test(a.city_district) ? a.city_district : "",
    a.town || a.city || a.village || a.municipality || "",
  ].map((x) => String(x || "").trim()).filter(Boolean);
  const vus: string[] = [];
  for (const p of parties) if (!vus.some((v) => v.toLowerCase() === p.toLowerCase())) vus.push(p);
  return vus.slice(0, 3).join(", ");
}

/* ---------- (4.8.0) Google ---------- */

type Composant = { long_name?: string; types?: string[] };

/** Le nom d'un point selon Google : « Sèdomey, Togoudo, Godomey ». On lit
    tous les résultats (du plus précis au plus large) et l'on garde, dans
    l'ordre, le quartier, l'arrondissement, la ville — trois au plus, sans
    doublon, sans « 12ᵉ Arrondissement » ni code « plus ». */
export function nomGoogle(resultats: { address_components?: Composant[] }[] | undefined): string {
  const RANGS = ["neighborhood", "sublocality_level_2", "sublocality_level_1", "sublocality",
    "administrative_area_level_3", "locality"];
  const parRang: Record<string, string> = {};
  for (const r of resultats || []) {
    for (const c of r.address_components || []) {
      const nom = String(c.long_name || "").trim();
      if (!nom || /^\d/.test(nom) || /Arrondissement/i.test(nom) || /\+/.test(nom)) continue;
      for (const t of c.types || []) if (RANGS.includes(t) && !parRang[t]) parRang[t] = nom;
    }
  }
  const vus: string[] = [];
  for (const t of RANGS) {
    const p = parRang[t];
    if (p && !vus.some((v) => v.toLowerCase() === p.toLowerCase())) vus.push(p);
  }
  return vus.slice(0, 3).join(", ");
}

/** Nommer par Google ; "" s'il ne dit rien, null s'il refuse ou tombe. */
async function nommerGoogle(lat: number, lng: number): Promise<string | null> {
  const r = await fetch("https://maps.googleapis.com/maps/api/geocode/json?language=fr&region=bj&latlng=" +
    lat + "," + lng + "&key=" + encodeURIComponent(cleGoogle()), { signal: AbortSignal.timeout(8000) });
  const d = await r.json().catch(() => ({})) as { status?: string; error_message?: string;
    results?: { address_components?: Composant[] }[] };
  if (!r.ok || (d.status !== "OK" && d.status !== "ZERO_RESULTS")) {
    console.error("Google Geocoding :", r.status, d.status ?? "", d.error_message ?? "");
    return null;
  }
  return nomGoogle(d.results);
}

type Lieu = { nom: string; detail: string; latitude: number; longitude: number };

/** Chercher par Google (Places, Text Search) ; null s'il refuse ou tombe. */
async function chercherGoogle(q: string): Promise<Lieu[] | null> {
  const [gauche, haut, droite, bas] = PREFERE.split(",").map(Number);
  const r = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": cleGoogle(),
      "X-Goog-FieldMask": "places.displayName,places.formattedAddress,places.location",
    },
    body: JSON.stringify({
      textQuery: q, languageCode: "fr", regionCode: "BJ", maxResultCount: 6,
      /* Le Grand Cotonou préféré, sans exclure le reste du pays. */
      locationBias: { rectangle: { low: { latitude: bas, longitude: gauche }, high: { latitude: haut, longitude: droite } } },
    }),
    signal: AbortSignal.timeout(8000),
  });
  const d = await r.json().catch(() => ({})) as { error?: { message?: string };
    places?: { displayName?: { text?: string }; formattedAddress?: string; location?: { latitude?: number; longitude?: number } }[] };
  if (!r.ok) {
    console.error("Google Places :", r.status, d.error?.message ?? "");
    return null;
  }
  return (d.places || []).map((x) => ({
    nom: String(x.displayName?.text || "").trim() || String(x.formattedAddress || "").split(",")[0].trim(),
    detail: String(x.formattedAddress || "").trim(),
    latitude: Number(x.location?.latitude), longitude: Number(x.location?.longitude),
  })).filter((x) => x.nom && dansLeBenin(x.latitude, x.longitude));
}

const dansLeBenin = (lat: number, lng: number) =>
  Number.isFinite(lat) && Number.isFinite(lng) &&
  lat >= BENIN.latMin && lat <= BENIN.latMax && lng >= BENIN.lngMin && lng <= BENIN.lngMax;

/* (3.76.0) OpenStreetMap refuse (HTTP 403) les adresses d'où partent les
   fonctions serveur, et répond à celles de la base. La question passe donc
   par la base (pg_net) : on la dépose, puis on vient lire la réponse. */
const ATTENTE_MS = 9000;
const PAS_MS = 250;
const pause = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Un composant d'adresse sans rien que la base refuserait (« ' ( ) ! * ~ »). */
export const coder = (x: string) =>
  encodeURIComponent(x).replace(/[!'()*~]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());

export async function source(chemin: string, demander = base, attente = ATTENTE_MS, pas = PAS_MS): Promise<unknown> {
  const id = await demander("lieu_source_demander", { chemin });
  if (typeof id !== "number") throw new Error("source : question non déposée");
  const fin = Date.now() + attente;
  while (Date.now() < fin) {
    await pause(pas);
    const r = await demander("lieu_source_reponse", { demande: id }) as
      { statut?: number | null; corps?: string | null; erreur?: string | null } | null;
    if (!r) continue;                                    // pas encore là
    if (r.erreur) throw new Error("source : " + r.erreur);
    if (r.statut !== 200) throw new Error("source : HTTP " + r.statut);
    return JSON.parse(String(r.corps || "null"));
  }
  throw new Error("source : pas de réponse en " + Math.round(attente / 1000) + " s");
}

Deno.serve(async (requete) => {
  if (requete.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (requete.method !== "POST") return json({ erreur: "Méthode non permise" }, 405);
  if (!BASE || !SERVICE) return json({ erreur: "Fonction mal réglée." }, 500);
  const corps = await requete.json().catch(() => ({})) as Record<string, unknown>;
  const action = String(corps.action || "");

  try {
    if (action === "nommer") {
      const lat = Number(corps.latitude), lng = Number(corps.longitude);
      if (!dansLeBenin(lat, lng)) return json({ nom: null, message: "Hors du Bénin." }, 400);
      const connu = await base("lieu_connu", { latitude: lat, longitude: lng }) as
        { nom?: string | null; plafond_atteint?: boolean } | null;
      if (connu && connu.nom) return json({ nom: connu.nom, cache: true });
      if (connu && connu.plafond_atteint) return json({ nom: null, message: "Plafond du jour atteint." });
      /* (4.8.0) Google d'abord ; il ne dit rien ou refuse : OpenStreetMap. */
      if (cleGoogle()) {
        const g = await nommerGoogle(lat, lng).catch((err) => {
          console.error("Google Geocoding :", err instanceof Error ? err.message : err);
          return null;
        });
        if (g) {
          await base("noter_lieu", { latitude: lat, longitude: lng, nom: g, la_source: "google" });
          return json({ nom: g, cache: false, source: "google" });
        }
      }
      const r = await source("/reverse?format=jsonv2&zoom=17&addressdetails=1&lat=" + lat + "&lon=" + lng) as
        { address?: Adresse; name?: string } | null;
      const nom = nomDuLieu(r?.address);
      if (!nom) return json({ nom: null });
      await base("noter_lieu", { latitude: lat, longitude: lng, nom });
      return json({ nom, cache: false });
    }

    if (action === "chercher") {
      const q = String(corps.q || "").replace(/\s+/g, " ").trim().slice(0, 80);
      if (q.length < 2) return json({ resultats: [] });
      const connu = await base("lieu_connu", { latitude: 6.37, longitude: 2.39 }) as { plafond_atteint?: boolean } | null;
      if (connu && connu.plafond_atteint) return json({ resultats: [], message: "Plafond du jour atteint." });
      if (cleGoogle()) {
        const g = await chercherGoogle(q).catch((err) => {
          console.error("Google Places :", err instanceof Error ? err.message : err);
          return null;
        });
        if (g && g.length) {
          await base("compter_recherche_lieu", {}).catch(() => null);
          return json({ resultats: g, source: "google" });
        }
      }
      const r = await source("/search?format=jsonv2&addressdetails=1&limit=6&countrycodes=bj&viewbox=" + PREFERE +
        "&bounded=0&q=" + coder(q)) as { lat?: string; lon?: string; name?: string; address?: Adresse;
          display_name?: string }[] | null;
      const resultats = (Array.isArray(r) ? r : []).map((x) => ({
        nom: nomDuLieu(x.address, x.name) || String(x.display_name || "").split(",").slice(0, 3).join(","),
        detail: String(x.display_name || "").split(",").slice(0, 5).join(",").trim(),
        latitude: Number(x.lat), longitude: Number(x.lon),
      })).filter((x) => dansLeBenin(x.latitude, x.longitude));
      await base("compter_recherche_lieu", {}).catch(() => null);
      return json({ resultats });
    }
  } catch (err) {
    console.error("lieu :", err instanceof Error ? err.message : err);
    /* Le nom d'un lieu est un confort : son absence ne bloque rien. */
    return json(action === "chercher" ? { resultats: [], message: "Recherche indisponible." }
                                      : { nom: null, message: "Nom indisponible." });
  }
  return json({ erreur: "action inconnue" }, 400);
});
