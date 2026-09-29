/* Accord préalable aux règles de publication des professionnels.
   L'accord est propre au compte sur cet appareil. Il ne conditionne pas
   la lecture du catalogue, des commandes ou des livraisons. */
const ConditionsUGC = (() => {
  const VERSION = "2026-09-29";
  const PREFIXE = "bizzoo-conditions-publication:";
  const accordsSession = new Set();
  const demandes = new Map();

  function accordValide(cle) {
    if (accordsSession.has(cle)) return true;
    try { return localStorage.getItem(cle) === VERSION; }
    catch (_) { return false; }
  }

  function demander(cle) {
    return new Promise((resolve, reject) => {
      const fond = document.createElement("div");
      fond.className = "conditions-ugc-fond";
      fond.innerHTML =
        '<section class="conditions-ugc-boite" role="dialog" aria-modal="true" ' +
          'aria-labelledby="conditions-ugc-titre">' +
          '<h2 id="conditions-ugc-titre">Avant de publier sur BIZZOO</h2>' +
          '<p>Les fiches, photos, vidéos et réponses que vous publiez doivent être ' +
            'exactes, licites et vous appartenir ou être utilisées avec autorisation. ' +
            'Le harcèlement, la haine, les contenus sexuels explicites, les données ' +
            'personnelles d’autrui, la fraude et le spam sont interdits.</p>' +
          '<p>Consultez les <a href="legal/conditions.html">' +
            'conditions d’utilisation</a> avant de continuer.</p>' +
          '<label><input type="checkbox" data-ugc-accord> ' +
            'J’accepte les conditions et les règles de publication.</label>' +
          '<div class="btn-rangee">' +
            '<button type="button" class="btn btn-clair" data-ugc-annuler>Continuer sans publier</button>' +
            '<button type="button" class="btn" data-ugc-valider>Accepter et publier</button>' +
          '</div>' +
        '</section>';
      document.body.appendChild(fond);
      const finir = (accepte) => {
        fond.remove();
        if (accepte) {
          accordsSession.add(cle);
          try { localStorage.setItem(cle, VERSION); } catch (_) { /* session courante */ }
          resolve();
        } else {
          reject(new Error("Acceptez les conditions pour publier ce contenu."));
        }
      };
      fond.querySelector("[data-ugc-annuler]").onclick = () => finir(false);
      fond.querySelector("[data-ugc-valider]").onclick = () => {
        if (!fond.querySelector("[data-ugc-accord]").checked) {
          UI.toast("Cochez la case pour accepter les conditions.", "alerte");
          return;
        }
        finir(true);
      };
      fond.querySelector("[data-ugc-accord]").focus();
    });
  }

  function assurer() {
    const id = Supabase.identifiant();
    if (!id) return Promise.reject(new Error("Connectez-vous pour publier du contenu."));
    const cle = PREFIXE + id;
    if (accordValide(cle)) return Promise.resolve();
    if (demandes.has(cle)) return demandes.get(cle);
    const demande = demander(cle).finally(() => demandes.delete(cle));
    demandes.set(cle, demande);
    return demande;
  }

  return { assurer };
})();
