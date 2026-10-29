/* =========================================================
   BIZZOO — la distance PAR LA ROUTE, du point BIZZOO au client (3.70.0)

   Les frais de livraison se comptent du point BIZZOO jusqu'au client.
   Sans cette fonction, la distance est à vol d'oiseau × 1,3 : une
   moyenne, qu'une lagune ou un pont mettent en défaut. Avec elle, c'est
   le trajet que Google calcule (Routes API, « computeRoutes »).

   L'application appelle cette fonction dès qu'elle connaît où livrer.
   La fonction :

     1. demande à la base (clé de service) le point BIZZOO, et si la
        distance de ce client est déjà connue (à 50 m près) — elle l'est
        dès la seconde commande depuis chez lui : pas de nouvel appel ;
     2. sinon, demande le trajet à Google, et l'écrit dans la base
        (« enregistrer_route ») ;
     3. rend la distance. C'est la BASE, et elle seule, qui s'en sert
        pour figer les frais (« devis_livraison » dans « creer_commande ») :
        ce que rend cette fonction n'est qu'un aperçu pour l'écran, et
        l'application ne peut pas écrire une distance de son choix.

   SANS CLÉ, ELLE NE FAIT RIEN : { actif: false }, et tout continue à vol
   d'oiseau × coefficient. Google injoignable, refus, plafond du jour
   atteint : même chose — une commande ne bloque jamais sur Google.

   ---------------------------------------------------------
   Mise en service (une fois)
   ---------------------------------------------------------
     1. Google Cloud : projet, facturation, « Routes API » activée, une
        clé API restreinte à « Routes API » (README, « La distance par la
        route ») ;
     2. Supabase → Edge Functions → Secrets : GOOGLE_MAPS_KEY = la clé ;
     3. supabase functions deploy distance-route --no-verify-jwt
        (les clients commandent sans compte ; rien de ce que l'appel
        apporte n'est cru, hormis une position — bornée, et plafonnée
        par jour dans la base).
   ========================================================= */

const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
/* Lue à chaque appel : poser ou retirer le secret prend effet aussitôt. */
const cleGoogle = () => (Deno.env.get("GOOGLE_MAPS_KEY") ?? "").trim();

/* Au-delà, ce n'est pas une livraison BIZZOO : on ne paie pas Google pour
   un point posé à l'autre bout du monde. */
const VOL_OISEAU_MAX_KM = 150;

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

type Connue = {
  point?: boolean;
  invalide?: boolean;
  origine?: { latitude: number; longitude: number };
  distance_m?: number | null;
  vol_oiseau_km?: number;
  plafond_atteint?: boolean;
};

/** Le trajet selon Google, en mètres ; null si Google ne le donne pas. */
async function trajetGoogle(o: { latitude: number; longitude: number },
                            d: { latitude: number; longitude: number }): Promise<number | null> {
  const r = await fetch("https://routes.googleapis.com/directions/v2:computeRoutes", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": cleGoogle(),
      /* La distance seule : le moins cher des tarifs (« Essentials »). */
      "X-Goog-FieldMask": "routes.distanceMeters",
    },
    body: JSON.stringify({
      origin: { location: { latLng: o } },
      destination: { location: { latLng: d } },
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_UNAWARE",
      languageCode: "fr",
      units: "METRIC",
    }),
    signal: AbortSignal.timeout(8000),
  });
  const donnees = await r.json().catch(() => ({})) as { routes?: { distanceMeters?: number }[];
    error?: { message?: string } };
  if (!r.ok) {
    console.error("Google Routes :", r.status, donnees.error?.message ?? "");
    return null;
  }
  const m = Number(donnees.routes?.[0]?.distanceMeters);
  return Number.isFinite(m) && m > 0 ? Math.round(m) : null;
}

Deno.serve(async (requete) => {
  if (requete.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (requete.method !== "POST") return json({ actif: false, message: "Méthode non permise" }, 405);

  /* PAS DE CLÉ : rien à faire, et on le dit vite — l'application garde
     son estimation sans attendre. */
  if (!cleGoogle()) return json({ actif: false });
  if (!BASE || !SERVICE) return json({ actif: false, message: "Fonction mal réglée." }, 500);

  const corps = await requete.json().catch(() => ({})) as { latitude?: unknown; longitude?: unknown };
  const latitude = Number(corps.latitude);
  const longitude = Number(corps.longitude);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
      Math.abs(latitude) > 90 || Math.abs(longitude) > 180 || (latitude === 0 && longitude === 0)) {
    return json({ actif: true, distance_km: null, message: "Position invalide." }, 400);
  }

  try {
    const connue = await base("route_connue", { latitude, longitude }) as Connue | null;
    if (!connue || !connue.point || !connue.origine) return json({ actif: false });
    if (connue.invalide) return json({ actif: true, distance_km: null, message: "Position invalide." }, 400);
    if (connue.distance_m) {
      return json({ actif: true, distance_km: Math.round(connue.distance_m) / 1000, cache: true });
    }
    if (Number(connue.vol_oiseau_km) > VOL_OISEAU_MAX_KM) {
      return json({ actif: true, distance_km: null, message: "Trop loin du point BIZZOO." });
    }
    if (connue.plafond_atteint) {
      console.error("distance-route : plafond du jour atteint, estimation à vol d'oiseau.");
      return json({ actif: true, distance_km: null, message: "Plafond du jour atteint." });
    }
    const m = await trajetGoogle(connue.origine, { latitude, longitude });
    if (!m) return json({ actif: true, distance_km: null, message: "Google n'a pas rendu de trajet." });
    await base("enregistrer_route", { latitude, longitude, distance_m: m });
    return json({ actif: true, distance_km: m / 1000, cache: false });
  } catch (err) {
    console.error("distance-route :", err instanceof Error ? err.message : err);
    /* Une commande ne bloque jamais sur Google : l'application garde son
       estimation, et la base celle du vol d'oiseau. */
    return json({ actif: true, distance_km: null, message: "Distance par la route indisponible." });
  }
});
