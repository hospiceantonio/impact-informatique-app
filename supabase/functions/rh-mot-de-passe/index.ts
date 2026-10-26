/* =========================================================
   BIZZOO Personnel — l'administration redonne un mot de passe

   Un employé a oublié son mot de passe : depuis sa fiche, un membre
   de l'administration lui en donne un provisoire. Changer le mot de
   passe d'un AUTRE compte demande la clé de service de Supabase :
   c'est pourquoi ce geste passe par ici, où la clé reste.

   CE QUI NE SE DISCUTE PAS :
   - LE DROIT se vérifie dans la base, avec la session de
     l'administrateur (rh_mdp_preparer) : la fonction n'en décide rien,
     et elle ne change que le compte que la base lui rend ;
   - le mot de passe provisoire ne passe que par la requête et l'API de
     Supabase : il n'est ni gardé, ni écrit dans le journal ;
   - ensuite (rh_mdp_conclure) : le compte attend que l'employé choisisse
     le sien, ses sessions ouvertes sont fermées, le geste est noté.

   Déploiement (avec la vérification du jeton : seul un compte
   connecté l'appelle) :
     supabase functions deploy rh-mot-de-passe
   ========================================================= */

const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const repondre = (corps: Record<string, unknown>, statut = 200) =>
  new Response(JSON.stringify(corps), { status: statut, headers: { ...CORS, "Content-Type": "application/json" } });

/** Un appel à la base, avec le jeton de l'appelant ou les droits du service. */
async function rpc(nom: string, parametres: Record<string, unknown>, jeton?: string): Promise<unknown> {
  const r = await fetch(BASE + "/rest/v1/rpc/" + nom, {
    method: "POST",
    headers: {
      apikey: jeton ? ANON : SERVICE,
      Authorization: "Bearer " + (jeton ?? SERVICE),
      "Content-Type": "application/json",
    },
    body: JSON.stringify(parametres),
  });
  const texte = await r.text();
  if (!r.ok) {
    let message = texte.slice(0, 300);
    try { message = JSON.parse(texte).message || message; } catch (_) { /* texte brut */ }
    throw new Error(message);
  }
  try { return JSON.parse(texte); } catch (_) { return null; }
}

Deno.serve(async (requete: Request): Promise<Response> => {
  if (requete.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (requete.method !== "POST") return repondre({ erreur: "POST seulement" }, 405);
  if (!BASE || !SERVICE || !ANON) return repondre({ erreur: "fonction mal configurée" }, 500);
  const jeton = (requete.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jeton || jeton === ANON) return repondre({ erreur: "Connectez-vous." }, 401);

  let corps: Record<string, unknown> = {};
  try { corps = await requete.json(); } catch (_) { /* corps vide */ }
  const employe = String(corps.employe || "");
  const motDePasse = String(corps.mot_de_passe || "");
  const motif = String(corps.motif || "").slice(0, 300);
  if (motDePasse.length < 8) return repondre({ erreur: "Le mot de passe provisoire fait 8 caractères au moins." }, 400);

  // Qui appelle : le compte de la session.
  const moi = await fetch(BASE + "/auth/v1/user", { headers: { apikey: ANON, Authorization: "Bearer " + jeton } });
  if (!moi.ok) return repondre({ erreur: "Session expirée : reconnectez-vous." }, 401);
  const par = String(((await moi.json()) as Record<string, unknown>).id || "");

  // Le droit, et le compte à traiter : c'est la base qui les donne.
  let compte: string;
  try {
    compte = String(await rpc("rh_mdp_preparer", { qui: employe }, jeton));
  } catch (err) {
    return repondre({ erreur: (err as Error).message }, 403);
  }

  const r = await fetch(BASE + "/auth/v1/admin/users/" + encodeURIComponent(compte), {
    method: "PUT",
    headers: { apikey: SERVICE, Authorization: "Bearer " + SERVICE, "Content-Type": "application/json" },
    body: JSON.stringify({ password: motDePasse }),
  });
  if (!r.ok) {
    const d = await r.json().catch(() => ({})) as Record<string, unknown>;
    const code = String(d.error_code || d.code || "");
    console.error("rh-mot-de-passe : refus de l'API", r.status, code);
    return repondre({ erreur: code === "weak_password" ? "Mot de passe trop faible : choisissez-en un plus long."
      : "Le mot de passe n'a pas pu être changé (" + r.status + ")." }, 400);
  }

  try {
    await rpc("rh_mdp_conclure", { qui: employe, compte, par, motif });
  } catch (err) {
    console.error("rh-mot-de-passe : conclusion", (err as Error).message);
    return repondre({ erreur: "Le mot de passe est changé, mais la suite a échoué : réessayez." }, 500);
  }
  return repondre({ ok: true });
});
