/* =========================================================
   SuiviPosition — la position du livreur pendant ses courses

   Tant qu'un livreur a une course en cours, BIZZOO Personnel le
   voit sur sa carte (« Localiser un livreur »). Sa position part
   d'ici :

   - dans l'APK, par le service Android « ServiceSuiviPosition »,
     qui continue application fermée et s'arrête de lui-même quand
     la base répond qu'il n'a plus de course ;
   - dans un navigateur, par la page, tant qu'elle est ouverte.

   Ni l'un ni l'autre ne tient la session du compte : la base donne
   un JETON DE SUIVI (« ouvrir_suivi_livreur »), qui ne sert qu'à
   écrire la position de ce livreur (« position_en_course »).
   ========================================================= */
const SuiviPosition = (() => {
  /* Un jeton dure 16 heures ; on en redemande un au plus toutes les
     10 minutes, quand l'écran des courses se relit. */
  const RENOUVELER = 10 * 60 * 1000;
  const INTERVALLE = 20 * 1000;
  let ouvertLe = 0;
  let surveillance = null;
  let dernierEnvoi = 0;
  let jeton = "";

  const pont = () => (typeof window.AndroidPont !== "undefined" ? window.AndroidPont : null);
  const natif = () => { const p = pont(); return !!(p && typeof p.demarrerSuivi === "function"); };

  /** Les courses de l'écran viennent d'être lues : suivre, ou s'arrêter. */
  async function mettreAJour(courses) {
    const enCourse = (courses || []).some((c) => c.etat !== "remise");
    if (!enCourse) return arreter();
    if (Date.now() - ouvertLe < RENOUVELER && (natif() || surveillance !== null)) return;
    let r = null;
    try {
      r = await Supabase.rpcLecture("ouvrir_suivi_livreur", {});
    } catch (_) {
      return;   // base d'avant, ou réseau : les courses s'affichent quand même
    }
    if (!r || !r.jeton || !r.en_course) return arreter();
    const c = Supabase.configuration();
    if (!c) return;
    ouvertLe = Date.now();
    jeton = r.jeton;
    if (natif()) {
      try { pont().demarrerSuivi(c.url, c.cle, r.jeton); } catch (_) { /* le service n'a pas pu démarrer */ }
      return;
    }
    suivreDepuisLaPage(c);
  }

  /* ---------- Sans l'APK : la page, tant qu'elle est ouverte ---------- */

  function suivreDepuisLaPage(c) {
    if (surveillance !== null || !navigator.geolocation) return;
    surveillance = navigator.geolocation.watchPosition((p) => {
      if (Date.now() - dernierEnvoi < INTERVALLE) return;
      dernierEnvoi = Date.now();
      envoyer(c, p.coords);
    }, () => { /* refusée ou introuvable : rien à envoyer */ },
    { enableHighAccuracy: true, maximumAge: 15000, timeout: 30000 });
  }

  async function envoyer(c, coords) {
    try {
      const r = await fetch(c.url + "/rest/v1/rpc/position_en_course", {
        method: "POST",
        headers: { "apikey": c.cle, "Content-Type": "application/json" },
        body: JSON.stringify({ jeton, lat: coords.latitude, lng: coords.longitude,
                               precision_m: Math.round(coords.accuracy || 0) }),
      });
      const d = await r.json().catch(() => null);
      if (!r.ok || (d && d.continuer === false)) arreter();
    } catch (_) { /* réseau : la prochaine position repartira */ }
  }

  /** Plus de course, ou déconnexion : le téléphone cesse de suivre. */
  function arreter() {
    if (surveillance !== null && navigator.geolocation) navigator.geolocation.clearWatch(surveillance);
    surveillance = null;
    ouvertLe = 0;
    jeton = "";
    const p = pont();
    if (p && typeof p.arreterSuivi === "function") {
      try { p.arreterSuivi(); } catch (_) { /* vide */ }
    }
  }

  return { mettreAJour, arreter };
})();
