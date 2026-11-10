/* =========================================================
   PushWeb — les notifications dans le NAVIGATEUR (3.80.0)

   Sans l'application Android, BIZZOO n'avait aucun moyen de réveiller
   quelqu'un : un client sur le site, une boutique, un vendeur ou un
   livreur dans le navigateur ne voyait rien tant qu'il n'ouvrait pas
   l'écran. Le navigateur sait pourtant recevoir une notification « Web
   Push », même le site fermé (Android, ordinateur ; iPhone : BIZZOO
   ajouté à l'écran d'accueil). Il suffit que la personne l'autorise, une
   fois.

   Le même fichier dans l'application client et dans l'administration.

     PushWeb.monter(element, { application, rpc }) → la carte « Notifications
                                                      sur ce navigateur »
     PushWeb.rafraichir({ application, rpc })        → à l'ouverture, connecté :
                                                      ce navigateur, s'il est
                                                      abonné, sonne pour CE compte
     PushWeb.oublier()                               → à la déconnexion

   « rpc(nom, corps) » est l'appel de l'application, AVEC la session du
   compte (Compte.rpc chez le client, Supabase.rpc dans l'administration).

   La base garde l'abonnement (« appareils_web ») ; la fonction Edge
   « envoyer-push » chiffre et envoie ; le service worker (sw.js) affiche
   la notification et ouvre le bon écran au toucher. Dans l'application
   Android, rien de tout cela : Firebase s'en charge déjà.
   ========================================================= */
const PushWeb = (() => {

  const CLE = "bizzoo-push-web";              // l'abonnement déclaré pour un compte
  const CLE_A_OUBLIER = "bizzoo-push-web-a-oublier";

  const dansApplication = () => typeof window.AndroidPont !== "undefined";
  const possible = () => !dansApplication() && "serviceWorker" in navigator &&
    "PushManager" in window && "Notification" in window;
  const iphone = () => /iPhone|iPad|iPod/.test(navigator.userAgent || "");
  const ecranAccueil = () => {
    try { return window.matchMedia("(display-mode: standalone)").matches || navigator.standalone === true; }
    catch (_) { return false; }
  };

  const lire = (cle) => { try { return localStorage.getItem(cle) || ""; } catch (_) { return ""; } };
  const ecrire = (cle, v) => {
    try { if (v) localStorage.setItem(cle, v); else localStorage.removeItem(cle); } catch (_) { /* vide */ }
  };

  /* La base, sans session : la clé publique et l'oubli d'un abonnement. */
  function configuration() {
    let url = "", c = "";
    try {
      const brut = localStorage.getItem("impact-config");
      if (brut) { const x = JSON.parse(brut); url = x.url || ""; c = x.cle || ""; }
    } catch (_) { /* configuration locale illisible */ }
    if (!url && typeof CONFIG !== "undefined") {
      url = CONFIG.SUPABASE_URL || "";
      c = CONFIG.SUPABASE_ANON_KEY || "";
    }
    url = String(url).trim().replace(/\/+$/, "");
    return /^https:\/\//.test(url) && c ? { url, cle: String(c).trim() } : null;
  }
  async function appelPublic(nom, corps) {
    const c = configuration();
    if (!c) throw new Error("Base non configurée");
    const r = await fetch(c.url + "/rest/v1/rpc/" + nom, {
      method: "POST",
      headers: { "apikey": c.cle, "Content-Type": "application/json" },
      body: JSON.stringify(corps || {}),
    });
    if (!r.ok) throw new Error("HTTP " + r.status);
    return r.json().catch(() => null);
  }

  const octets = (b64) => {
    const b = String(b64).replace(/-/g, "+").replace(/_/g, "/");
    const brut = atob(b + "===".slice((b.length + 3) % 4));
    return Uint8Array.from(brut, (x) => x.charCodeAt(0));
  };

  async function enregistrement() {
    if (!possible()) return null;
    try {
      /* Déjà actif : tout de suite. Sinon on l'attend, mais pas plus de
         quatre secondes (un navigateur qui refuse les service workers). */
      const deja = await navigator.serviceWorker.getRegistration();
      if (deja && deja.active) return deja;
      return await Promise.race([
        navigator.serviceWorker.ready,
        new Promise((r) => setTimeout(() => r(null), 4000)),
      ]);
    } catch (_) {
      return null;
    }
  }
  async function abonnementActuel() {
    const reg = await enregistrement();
    if (!reg || !reg.pushManager) return null;
    try { return await reg.pushManager.getSubscription(); } catch (_) { return null; }
  }

  /** « indisponible », « ecran-accueil » (iPhone), « refusee », « active » ou « inactive ». */
  async function etat() {
    if (dansApplication()) return "application";
    if (iphone() && !ecranAccueil()) return "ecran-accueil";
    if (!possible()) return "indisponible";
    if (Notification.permission === "denied") return "refusee";
    const abo = await abonnementActuel();
    return abo && Notification.permission === "granted" && lire(CLE) === abo.endpoint ? "active" : "inactive";
  }

  async function declarer(abo, { application, rpc }) {
    const j = abo.toJSON();
    await rpc("enregistrer_navigateur", {
      point: j.endpoint, cle: (j.keys && j.keys.p256dh) || "", secret: (j.keys && j.keys.auth) || "",
      application,
    });
    ecrire(CLE, j.endpoint);
    ecrire(CLE_A_OUBLIER, "");
  }

  /** « Activer » : la permission, l'abonnement, et la base le sait. */
  async function activer(opts) {
    if (!possible()) throw new Error("Ce navigateur ne sait pas recevoir de notifications.");
    const permission = await Notification.requestPermission();
    if (permission !== "granted") {
      throw new Error("Notifications refusées. Autorisez-les dans les réglages du navigateur pour ce site.");
    }
    const reg = await enregistrement();
    if (!reg) throw new Error("Rechargez la page, puis réessayez.");
    let abo = await reg.pushManager.getSubscription();
    if (!abo) {
      const cle = await appelPublic("cle_push_web", {}).catch(() => null);   // base d'avant la 3.80.0 : pas encore réglé
      if (!cle) throw new Error("Les notifications ne sont pas encore réglées chez BIZZOO.");
      abo = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: octets(cle) });
    }
    await declarer(abo, opts);
  }

  /** « Désactiver » : ce navigateur ne reçoit plus rien. */
  async function desactiver() {
    const abo = await abonnementActuel();
    ecrire(CLE, "");
    if (!abo) return;
    try { await appelPublic("oublier_navigateur", { point: abo.endpoint }); }
    catch (_) { ecrire(CLE_A_OUBLIER, abo.endpoint); }
    try { await abo.unsubscribe(); } catch (_) { /* vide */ }
  }

  /** À l'ouverture, connecté : un navigateur abonné sonne pour CE compte. */
  async function rafraichir(opts) {
    try {
      const enSuspens = lire(CLE_A_OUBLIER);
      if (enSuspens) {
        await appelPublic("oublier_navigateur", { point: enSuspens });
        ecrire(CLE_A_OUBLIER, "");
      }
      if (!possible() || Notification.permission !== "granted") return;
      const abo = await abonnementActuel();
      if (abo && lire(CLE) === abo.endpoint) await declarer(abo, opts);
    } catch (_) { /* sans réseau : à la prochaine ouverture */ }
  }

  /** À la déconnexion : un navigateur prêté ne sonne plus pour le compte d'avant. */
  async function oublier() {
    /* Rien de déclaré ici pour un compte : rien à oublier, et la
       déconnexion n'attend pas. */
    if (!possible() || !lire(CLE)) return;
    try { await desactiver(); } catch (_) { /* vide */ }
  }

  const echapper = (s) => String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

  const TEXTES = {
    active: "Activées sur ce navigateur : vous êtes prévenu même le site fermé.",
    inactive: "Recevez vos notifications sur ce navigateur, même le site fermé.",
    refusee: "Vous les avez refusées : autorisez les notifications pour ce site dans les réglages du navigateur, puis revenez ici.",
    "ecran-accueil": "Sur iPhone : touchez Partager puis « Sur l'écran d'accueil », ouvrez BIZZOO depuis l'écran d'accueil, puis revenez ici.",
    indisponible: "Ce navigateur ne sait pas recevoir de notifications. Essayez Chrome, Edge ou Firefox.",
  };

  /** La carte « Notifications sur ce navigateur » dans « element ». */
  async function monter(element, opts) {
    if (!element) return;
    const e = await etat();
    if (e === "application") { element.hidden = true; return; }
    element.hidden = false;
    element.innerHTML =
      '<div class="carte-titre">Notifications sur ce navigateur</div>' +
      '<p class="aide" id="pw-etat" style="margin:0 0 10px">' + echapper(TEXTES[e] || "") + "</p>" +
      (e === "active"
        ? '<button type="button" class="btn btn-clair" id="pw-desactiver">Désactiver</button>'
        : e === "inactive"
          ? '<button type="button" class="btn" id="pw-activer">Activer les notifications</button>'
          : "");
    const activerBtn = element.querySelector("#pw-activer");
    if (activerBtn) {
      activerBtn.onclick = async () => {
        activerBtn.disabled = true;
        try {
          await activer(opts);
          if (typeof UI !== "undefined") UI.toast("Notifications activées sur ce navigateur.", "ok");
        } catch (err) {
          if (typeof UI !== "undefined") UI.toast(err.message, "err");
        }
        monter(element, opts);
      };
    }
    const desactiverBtn = element.querySelector("#pw-desactiver");
    if (desactiverBtn) {
      desactiverBtn.onclick = async () => {
        desactiverBtn.disabled = true;
        await desactiver();
        if (typeof UI !== "undefined") UI.toast("Notifications désactivées sur ce navigateur.", "ok");
        monter(element, opts);
      };
    }
  }

  return { possible, etat, activer, desactiver, rafraichir, oublier, monter };
})();
