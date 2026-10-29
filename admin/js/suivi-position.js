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
  /* (3.70.0) Le suivi en cours est-il celui d'une course (rythme serré) ? */
  let suiviEnCourse = false;
  /* Ce que l'écran a dit la dernière fois : on le rejoue au retour au
     premier plan, pour relancer un service qu'Android aurait arrêté. */
  let dernierEtat = null;
  /* Un jeton obtenu page cachée : il partira au service au retour à l'écran
     (Android refuse de le relancer hors de l'écran). */
  let jetonEnAttente = "";
  /* Une mise à jour à la fois : deux renouvellements croisés laisseraient
     au service un jeton déjà remplacé. */
  let occupe = false;
  let aRejouer = false;

  const pont = () => (typeof window.AndroidPont !== "undefined" ? window.AndroidPont : null);
  const natif = () => { const p = pont(); return !!(p && typeof p.demarrerSuivi === "function"); };
  /* Le service Android tourne-t-il vraiment — et avec le jeton donné ? Une
     APK d'avant ne sait pas le dire : on la croit. */
  const serviceTourne = (avecJeton) => {
    const p = pont();
    if (!p) return false;
    try {
      if (avecJeton && typeof p.suiviAvec === "function") return !!p.suiviAvec(avecJeton);
      if (typeof p.suiviActif === "function") return !!p.suiviActif();
    } catch (_) { /* pont d'avant */ }
    return true;
  };

  /** Les courses de l'écran viennent d'être lues : suivre, ou s'arrêter.
      (3.70.0) « disponible » : libre, l'APK suit aussi, application fermée
      (toutes les 3 minutes) — c'est ce qui fait « le plus proche ». */
  async function mettreAJour(courses, disponible) {
    dernierEtat = { courses: courses || [], disponible: !!disponible };
    if (occupe) { aRejouer = true; return; }
    occupe = true;
    try {
      await suivre(courses, disponible);
    } finally {
      occupe = false;
      if (aRejouer && dernierEtat) {
        aRejouer = false;
        mettreAJour(dernierEtat.courses, dernierEtat.disponible);
      }
    }
  }

  async function suivre(courses, disponible) {
    const enCourse = (courses || []).some((c) => c.etat !== "remise");
    if (!enCourse && !(disponible && natif())) return arreter();
    const tourne = natif() ? serviceTourne(jeton) : surveillance !== null;
    /* Libre → en course : on relance tout de suite, pour le rythme serré. */
    const memeRythme = !(enCourse && !suiviEnCourse);
    if (Date.now() - ouvertLe < RENOUVELER && tourne && memeRythme) return;
    /* Page cachée, service en marche : on ne renouvelle pas le jeton. Android
       refuserait de relancer le service hors de l'écran, et l'ancien jeton
       remplacé finirait par ne plus valoir. Ce sera au retour à l'écran. */
    if (natif() && document.hidden && tourne) return;
    let r = null;
    try {
      r = await Supabase.rpcLecture("ouvrir_suivi_livreur", {});
    } catch (_) {
      return;   // base d'avant, ou réseau : les courses s'affichent quand même
    }
    /* Libre : seulement si la base le permet (elle répond « disponible »
       depuis la 3.70.0 ; une base d'avant ne suit que les courses). */
    const libre = r && r.disponible === true && disponible && natif();
    if (!r || !r.jeton || !(r.en_course || libre)) return arreter();
    const c = Supabase.configuration();
    if (!c) return;
    ouvertLe = Date.now();
    suiviEnCourse = !!r.en_course;
    jeton = r.jeton;
    if (natif()) {
      /* La page s'est cachée pendant la demande : le service recevra ce
         jeton au retour à l'écran (l'ancien vaut encore 10 minutes). */
      if (document.hidden) { jetonEnAttente = r.jeton; return; }
      demarrerNatif(c, r.jeton);
      return;
    }
    suivreDepuisLaPage(c);
  }

  function demarrerNatif(c, j) {
    jetonEnAttente = "";
    try { pont().demarrerSuivi(c.url, c.cle, j); } catch (_) { /* le service n'a pas pu démarrer */ }
    /* Android a pu refuser (permission demandée, démarrage interdit) : le
       prochain passage réessaiera au lieu d'attendre 10 minutes. */
    setTimeout(() => { if (!serviceTourne(j)) ouvertLe = 0; }, 4000);
  }

  /* Retour à l'écran : donner le jeton en attente, ou relancer ce
     qu'Android aurait arrêté entre-temps. */
  document.addEventListener("visibilitychange", () => {
    if (document.hidden || !dernierEtat || !natif()) return;
    const c = Supabase.configuration();
    if (jetonEnAttente && c) { demarrerNatif(c, jetonEnAttente); return; }
    if (!serviceTourne(jeton)) ouvertLe = 0;
    mettreAJour(dernierEtat.courses, dernierEtat.disponible);
  });

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

  /* ---------- (3.70.0) Le livreur libre : sa position, toutes les 3 minutes ----------
     La course va d'abord au livreur le plus proche : encore faut-il savoir
     où il est. Tant que BIZZOO Admin est ouvert (et visible), sa position
     part toutes les 3 minutes (« signaler_ma_position » ; la base ignore
     ce qui arrive moins de 30 secondes après la précédente). */
  const PRESENCE = 3 * 60 * 1000;
  let presenceMinuteur = null;
  let dernierePresence = 0;
  let presenceTic = null;

  /* Dans l'APK aussi : le service s'en charge application fermée ; la page
     ouverte en est le secours (la base ignore les doublons de 30 secondes). */
  function presence() {
    if (presenceMinuteur !== null || !navigator.geolocation) return;
    const tic = () => {
      if (document.hidden || Date.now() - dernierePresence < PRESENCE - 5000) return;
      dernierePresence = Date.now();
      navigator.geolocation.getCurrentPosition((p) => {
        Supabase.rpcLecture("signaler_ma_position", {
          lat: p.coords.latitude, lng: p.coords.longitude,
          precision_m: Math.round(p.coords.accuracy || 0),
        }).catch(() => { /* base d'avant, ou réseau : la prochaine partira */ });
      }, () => { /* refusée ou introuvable : rien à envoyer */ },
      { enableHighAccuracy: false, maximumAge: 60000, timeout: 20000 });
    };
    tic();
    presenceMinuteur = setInterval(tic, 30 * 1000);
    presenceTic = tic;
    document.addEventListener("visibilitychange", presenceTic);
  }

  function arreterPresence() {
    if (presenceMinuteur !== null) clearInterval(presenceMinuteur);
    if (presenceTic) document.removeEventListener("visibilitychange", presenceTic);
    presenceMinuteur = null;
    presenceTic = null;
    dernierePresence = 0;
  }

  /** Plus de course, ou déconnexion : le téléphone cesse de suivre. */
  function arreter() {
    /* (3.70.0) La base l'oublie aussi, s'il n'a plus rien à suivre (elle
       vérifie elle-même : course ou « disponible », elle garde). */
    if (jeton || ouvertLe) {
      Supabase.rpcLecture("fermer_suivi_livreur", { tout: false }).catch(() => { /* base d'avant */ });
    }
    if (surveillance !== null && navigator.geolocation) navigator.geolocation.clearWatch(surveillance);
    surveillance = null;
    ouvertLe = 0;
    suiviEnCourse = false;
    jetonEnAttente = "";
    jeton = "";
    const p = pont();
    if (p && typeof p.arreterSuivi === "function") {
      try { p.arreterSuivi(); } catch (_) { /* vide */ }
    }
  }

  /** Déconnexion : plus rien à rejouer au retour à l'écran. */
  function oublier() {
    dernierEtat = null;
    /* Déconnexion : le suivi s'arrête, course ou pas — la session encore
       valable le dit à la base. */
    Supabase.rpcLecture("fermer_suivi_livreur", { tout: true }).catch(() => { /* base d'avant */ });
    jeton = "";
    ouvertLe = 0;
    arreter();
    arreterPresence();
  }

  return { mettreAJour, arreter, presence, arreterPresence, oublier, natif };
})();
