/* =========================================================
   Fabrique les clés VAPID des alertes de BIZZOO Personnel.

   Une seule fois, sur le PC du propriétaire :
       node tools/vapid-cles.mjs

   Il affiche deux lignes :
     - VAPID_PUBLIQUE : à coller dans les secrets de la fonction Edge
       ET dans la base (rh_push_reglage.cle_publique) — elle n'a rien
       de secret, chaque téléphone la reçoit ;
     - VAPID_PRIVEE : à coller dans les secrets de la fonction Edge
       SEULEMENT (Supabase → Edge Functions → Secrets). Ne l'écrire
       nulle part ailleurs : ni dans un fichier du dépôt, ni dans une
       conversation. Perdue ou divulguée, on en refait une paire et
       chaque employé réactive ses alertes.

   Rien n'est écrit sur le disque, rien ne sort du PC.
   ========================================================= */
const paire = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const publique = Buffer.from(await crypto.subtle.exportKey("raw", paire.publicKey)).toString("base64url");
const privee = (await crypto.subtle.exportKey("jwk", paire.privateKey)).d;
console.log("VAPID_PUBLIQUE=" + publique);
console.log("VAPID_PRIVEE=" + privee);
console.log("VAPID_SUJET=mailto:<une adresse de BIZZOO>");
