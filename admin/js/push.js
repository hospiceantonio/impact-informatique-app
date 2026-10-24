/* =========================================================
   Push — faire sonner le téléphone, application fermée (3.65.0)

   Une course confiée à un livreur, une commande payée chez une
   boutique : la base prévient Firebase, qui réveille le téléphone —
   même quand BIZZOO Admin est fermée ou en veille.

   Ce fichier ne fait qu'une chose : DÉCLARER CE TÉLÉPHONE à la base,
   pour le compte connecté, avec le jeton que Firebase a donné à
   l'application Android (« AndroidPont.jetonPush »). Il le retire à la
   déconnexion : un téléphone prêté ne doit pas continuer de sonner pour
   le compte d'avant.

   Dans un navigateur, il n'y a pas de pont : rien ne se passe, et
   l'application sonne comme avant quand elle est ouverte.
   ========================================================= */
const Push = (() => {
  const CLE = "bizzoo-push-declare";
  const ESSAIS = 8;            // Firebase peut mettre quelques secondes à donner le jeton
  const INTERVALLE = 4000;
  let enCours = false;

  function jetonDuTelephone() {
    try {
      const pont = window.AndroidPont;
      if (!pont || typeof pont.jetonPush !== "function") return "";
      return String(pont.jetonPush() || "").trim();
    } catch (_) {
      return "";
    }
  }

  const lire = () => { try { return localStorage.getItem(CLE) || ""; } catch (_) { return ""; } };
  const ecrire = (v) => { try { if (v) localStorage.setItem(CLE, v); else localStorage.removeItem(CLE); } catch (_) { /* vide */ } };

  /** À chaque ouverture, une fois connecté : ce téléphone sonne pour ce compte. */
  async function declarer() {
    if (enCours || typeof window.AndroidPont === "undefined") return;
    enCours = true;
    try {
      for (let i = 0; i < ESSAIS; i++) {
        const jeton = jetonDuTelephone();
        if (jeton) {
          if (!Supabase.identifiant()) return;
          await Supabase.rpc("enregistrer_appareil", { jeton, application: "admin" });
          ecrire(jeton);
          return;
        }
        await new Promise((r) => setTimeout(r, INTERVALLE));
      }
    } catch (_) {
      /* Base d'avant les notifications push, ou réseau coupé : on
         réessaiera à la prochaine ouverture. */
    } finally {
      enCours = false;
    }
  }

  /** À la déconnexion, AVANT de rendre la session : ce téléphone se tait. */
  async function oublier() {
    const jeton = lire() || jetonDuTelephone();
    ecrire("");
    if (!jeton) return;
    try {
      await Supabase.rpc("oublier_appareil", { jeton });
    } catch (_) { /* la base l'oubliera au premier refus de Firebase */ }
  }

  return { declarer, oublier };
})();
