/* =========================================================
   Push — le client prévenu, application fermée (3.70.0)

   Commande payée, livreur trouvé, colis en route, colis livré : la base
   écrit la notification de l'acheteur, puis prévient Firebase, qui
   réveille SON téléphone — même quand BIZZOO est fermée. Il n'est plus
   absent quand le livreur arrive.

   Ce fichier ne fait qu'une chose : DÉCLARER CE TÉLÉPHONE à la base, pour
   le compte connecté, avec le jeton que Firebase a donné à l'application
   Android (« AndroidPont.jetonPush »). Il le retire à la déconnexion : un
   téléphone prêté ne doit pas continuer de sonner pour le compte d'avant.

   La base sait alors que ce client a l'application : elle ne lui envoie
   plus de SMS pour les mêmes étapes (sms_prevoir). D'où deux règles :
   - un téléphone qui REFUSE les notifications n'est pas déclaré (il est
     même retiré) : sinon ce client n'aurait ni notification ni SMS ;
   - un retrait raté (déconnexion sans réseau) est rejoué à la prochaine
     ouverture, sans session, avec le seul jeton.

   Dans un navigateur, ou sur iPhone, il n'y a pas de pont : rien ne se
   passe — ces clients-là sont prévenus par SMS.
   ========================================================= */
const Push = (() => {
  const CLE = "bizzoo-push-declare";
  const CLE_A_OUBLIER = "bizzoo-push-a-oublier";
  const ESSAIS = 8;            // Firebase peut mettre quelques secondes à donner le jeton
  const INTERVALLE = 4000;
  let enCours = null;          // la déclaration en cours : la déconnexion l'attend

  const pont = () => (typeof window.AndroidPont === "undefined" ? null : window.AndroidPont);
  function jetonDuTelephone() {
    try {
      const p = pont();
      if (!p || typeof p.jetonPush !== "function") return "";
      return String(p.jetonPush() || "").trim();
    } catch (_) {
      return "";
    }
  }
  /** Une coquille d'avant 3.70.0 ne sait pas le dire : on la croit. */
  function notificationsPermises() {
    try {
      const p = pont();
      return !p || typeof p.notificationsPermises !== "function" || p.notificationsPermises() !== false;
    } catch (_) {
      return true;
    }
  }

  const lire = (cle) => { try { return localStorage.getItem(cle) || ""; } catch (_) { return ""; } };
  const ecrire = (cle, v) => { try { if (v) localStorage.setItem(cle, v); else localStorage.removeItem(cle); } catch (_) { /* vide */ } };

  async function rattraperOubli() {
    const jeton = lire(CLE_A_OUBLIER);
    if (!jeton) return;
    try {
      /* Sans session : avec la clé publique, comme un visiteur. Seul ce
         téléphone connaît son jeton. */
      const c = Catalogue.configuration();
      if (!c) return;
      const r = await fetch(c.url + "/rest/v1/rpc/oublier_jeton_push", {
        method: "POST",
        headers: { "apikey": c.cle, "Content-Type": "application/json" },
        body: JSON.stringify({ jeton }),
      });
      if (r.ok) ecrire(CLE_A_OUBLIER, "");
    } catch (_) { /* toujours sans réseau : à la prochaine ouverture */ }
  }

  async function declarerVraiment() {
    for (let i = 0; i < ESSAIS; i++) {
      const jeton = jetonDuTelephone();
      if (jeton) {
        if (!Compte.connecte()) return;
        if (!notificationsPermises()) {
          /* Refusées : ce téléphone ne prévient personne — la base doit le
             savoir pour envoyer le SMS. */
          await Compte.rpc("oublier_appareil", { jeton });
          ecrire(CLE, "");
          return;
        }
        await Compte.rpc("enregistrer_appareil", { jeton, application: "client" });
        ecrire(CLE, jeton);
        ecrire(CLE_A_OUBLIER, "");
        return;
      }
      await new Promise((r) => setTimeout(r, INTERVALLE));
    }
  }

  /** À chaque ouverture, une fois connecté : ce téléphone sonne pour ce compte. */
  function declarer() {
    if (enCours || !pont()) return enCours;
    enCours = declarerVraiment()
      .catch(() => { /* réseau coupé : on réessaiera à la prochaine ouverture */ })
      .finally(() => { enCours = null; });
    return enCours;
  }

  /** À la déconnexion, AVANT de rendre la session : ce téléphone se tait. */
  async function oublier() {
    if (enCours) await enCours;
    const jeton = lire(CLE) || jetonDuTelephone();
    ecrire(CLE, "");
    if (!jeton) return;
    try {
      await Compte.rpc("oublier_appareil", { jeton });
    } catch (_) {
      /* Sans réseau : la base croirait ce client toujours joignable par
         notification. On le retirera à la prochaine ouverture. */
      ecrire(CLE_A_OUBLIER, jeton);
    }
  }

  /** À l'ouverture, sans compte : un retrait resté en suspens. */
  function demarrer() {
    if (pont() && !Compte.connecte()) rattraperOubli();
  }

  return { declarer, oublier, demarrer };
})();
