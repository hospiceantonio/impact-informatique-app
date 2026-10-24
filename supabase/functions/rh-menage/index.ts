/* =========================================================
   BIZZOO Personnel — le ménage des discussions

   Toute discussion s'efface au bout de 7 jours, texte et pièces
   jointes (photos, vidéos, audio). pg_cron appelle cette fonction
   chaque heure (personnel-pieces.sql). Elle :

   1. efface les messages de plus de 7 jours (rh_purger_messages) ;
   2. efface du stockage les fichiers qu'aucun message ne cite plus
      (rh_pieces_perimees) : ceux des messages effacés, et ceux
      d'un envoi abandonné en route.

   Un fichier de stockage ne s'efface que par l'API du stockage (la
   base refuse qu'on supprime ses lignes à la main) : c'est pourquoi
   ce ménage est une fonction, et pas seulement du SQL.

   CE QUE CETTE FONCTION GARANTIT. Elle ne lit rien dans la requête :
   pas d'adresse, pas de date, pas de fichier. N'importe qui peut donc
   l'appeler sans danger — elle n'efface que ce que la règle des
   7 jours efface de toute façon. D'où le déploiement SANS
   vérification du jeton (pg_cron n'en a pas) :

     supabase functions deploy rh-menage --no-verify-jwt
   ========================================================= */

const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SEAU = "rh-pieces";
/* L'API du stockage efface par paquets : on en garde de raisonnables. */
const PAQUET = 100;

const entetes = {
  apikey: SERVICE,
  Authorization: "Bearer " + SERVICE,
  "Content-Type": "application/json",
};

async function rpc(nom: string): Promise<unknown> {
  const r = await fetch(BASE + "/rest/v1/rpc/" + nom, { method: "POST", headers: entetes, body: "{}" });
  if (!r.ok) throw new Error(nom + " : " + r.status + " " + (await r.text()).slice(0, 200));
  return await r.json();
}

Deno.serve(async () => {
  try {
    const messages = await rpc("rh_purger_messages") as number;
    const chemins = await rpc("rh_pieces_perimees") as string[];
    let fichiers = 0;
    for (let i = 0; i < chemins.length; i += PAQUET) {
      const paquet = chemins.slice(i, i + PAQUET);
      const r = await fetch(BASE + "/storage/v1/object/" + SEAU, {
        method: "DELETE",
        headers: entetes,
        body: JSON.stringify({ prefixes: paquet }),
      });
      if (!r.ok) throw new Error("stockage : " + r.status + " " + (await r.text()).slice(0, 200));
      fichiers += paquet.length;
    }
    return Response.json({ ok: true, messages, fichiers });
  } catch (err) {
    console.error("rh-menage", err);
    return Response.json({ ok: false, erreur: String((err as Error).message ?? err) }, { status: 500 });
  }
});
